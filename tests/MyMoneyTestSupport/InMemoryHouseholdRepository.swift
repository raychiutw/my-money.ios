import Foundation
import MyMoneyDomain

/// 不連網路的家庭，記下建立、加入、邀請、移除、離開。
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var stored: Household?
    private var failure: RepositoryError?
    private let gate: Gate?

    public private(set) var createdNames: [String] = []
    public private(set) var joinedCodes: [String] = []
    public private(set) var removedIDs: [UserID] = []
    public private(set) var inviteCount = 0
    public private(set) var leaveCount = 0

    /// 有家庭時回傳的代墊統計(後端一律每位成員一筆)。
    private var storedAdvances: [HouseholdAdvance]

    /// 撥款報銷送出過的內容，依送出順序。
    public private(set) var reimbursements: [Reimbursement] = []

    public init(household: Household?, advances: [HouseholdAdvance] = [], gate: Gate? = nil) {
        stored = household
        storedAdvances = advances
        self.gate = gate
    }

    /// 登入的範例帳號用個人現金替家裡墊付了晚餐 250,還沒報銷。
    public static let myPendingAdvance = HouseholdAdvance(
        memberID: InMemoryAuthRepository.Member.sample.user.id,
        memberName: InMemoryAuthRepository.Member.sample.user.name,
        totalAdvanced: Money(250),
        totalReimbursed: .zero,
        pendingReimbursement: Money(250),
        advanceItems: [AdvanceItem(
            id: TransactionID("sample-advance"), date: CalendarDay(year: 2026, month: 9, day: 28), category: .dining,
            note: "全家晚餐", amount: Money(250), accountName: "iOS 測試皮夾", accountKind: .cash
        )],
        reimbursementItems: [],
        receivingAccounts: [
            ReceivingAccount(id: SampleAccounts.savings.id, name: SampleAccounts.savings.name, kind: .bank),
            ReceivingAccount(id: SampleAccounts.wallet.id, name: SampleAccounts.wallet.name, kind: .cash),
        ]
    )

    /// 另一位家庭成員小美：待報銷 600,可收款帳戶是她的活存帳戶「小美薪轉」(替其他成員撥款報銷，#47)。
    public static let meiPendingAdvance = HouseholdAdvance(
        memberID: UserID("sample-mei"), memberName: "小美", totalAdvanced: Money(600), totalReimbursed: .zero,
        pendingReimbursement: Money(600), advanceItems: [], reimbursementItems: [],
        receivingAccounts: [ReceivingAccount(id: AccountID("mei-bank"), name: "小美薪轉", kind: .bank)]
    )

    /// 取過幾次代墊統計(帳戶頁的待報銷橫幅只在公帳範圍才取)。
    public private(set) var advancesCallCount = 0

    public func advances() async throws -> [HouseholdAdvance] {
        advancesCallCount += 1
        if let failure { throw failure }
        return stored == nil ? [] : storedAdvances
    }

    /// 跟後端一樣記下已報銷，待報銷減少(最小 0),並多一筆報銷明細。
    public func reimburse(_ reimbursement: Reimbursement) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        reimbursements.append(reimbursement)
        var name = "成員"
        storedAdvances = storedAdvances.map { advance in
            guard advance.memberID == reimbursement.memberID else { return advance }
            name = advance.memberName
            let reimbursed = advance.totalReimbursed + reimbursement.amount
            return HouseholdAdvance(
                memberID: advance.memberID,
                memberName: advance.memberName,
                totalAdvanced: advance.totalAdvanced,
                totalReimbursed: reimbursed,
                pendingReimbursement: max(advance.totalAdvanced - reimbursed, .zero),
                advanceItems: advance.advanceItems,
                reimbursementItems: [ReimbursementItem(
                    id: TransactionID("in-memory-reimbursement-\(reimbursements.count)"), date: reimbursement.date,
                    amount: reimbursement.amount, note: reimbursement.note, accountName: "收款帳戶"
                )] + advance.reimbursementItems,
                receivingAccounts: advance.receivingAccounts
            )
        }
        // 後端 `f32ff6c` 的原文(B:handlers/households.ts@f32ff6c:345)。
        return "成功從共同基金撥款報銷 NT$ \(reimbursement.amount.backendText) 給 \(name)！"
    }

    /// 「我們家」:小明(就是登入的範例帳號)和小美;`myRole` 是小明的角色(預設家庭管理員)，小美是另一個角色，
    /// 名冊跟 `myRole` 一致。
    public static func sample(
        myRole: HouseholdRole = .admin, advances: [HouseholdAdvance] = [], gate: Gate? = nil
    ) -> InMemoryHouseholdRepository {
        let joined = Date(timeIntervalSince1970: 1_790_000_000)
        return InMemoryHouseholdRepository(household: Household(name: "我們家", myRole: myRole, members: [
            me(role: myRole, joinedAt: joined),
            HouseholdMember(
                userID: UserID("sample-mei"), name: "小美", email: "mei@example.com", role: myRole == .admin ? .member : .admin,
                joinedAt: joined.addingTimeInterval(86_400)
            ),
        ]), advances: advances, gate: gate)
    }

    public func current() async throws -> Household? {
        if let failure { throw failure }
        return stored
    }

    /// 跟後端一樣：建立的人是家庭管理員，也是唯一的成員。
    public func create(name: String) async throws {
        if let failure { throw failure }
        createdNames.append(name)
        stored = Household(name: name, myRole: .admin, members: [Self.me(role: .admin, joinedAt: .now)])
    }

    public func join(code: String) async throws {
        if let failure { throw failure }
        joinedCodes.append(code)
        stored = Household(name: "阿公家", myRole: .member, members: [Self.me(role: .member, joinedAt: .now)])
    }

    public func invite() async throws -> HouseholdInvitation {
        await gate?.pass()
        if let failure { throw failure }
        inviteCount += 1
        return HouseholdInvitation(code: "FAM-TST\(inviteCount)", expiresAt: .now.addingTimeInterval(7 * 86_400))
    }

    public func leave() async throws {
        if let failure { throw failure }
        leaveCount += 1
        stored = nil
    }

    public func removeMember(_ userID: UserID) async throws {
        if let failure { throw failure }
        removedIDs.append(userID)
        if let household = stored {
            stored = Household(name: household.name, myRole: household.myRole, members: household.members.filter { $0.userID != userID })
        }
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 之後的請求恢復正常。
    public func clearFailure() {
        failure = nil
    }

    /// 登入的範例帳號。
    private static func me(role: HouseholdRole, joinedAt: Date) -> HouseholdMember {
        let user = InMemoryAuthRepository.Member.sample.user
        return HouseholdMember(userID: user.id, name: user.name, email: user.email, role: role, joinedAt: joinedAt)
    }
}
