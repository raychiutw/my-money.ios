import Foundation
import MyMoneyDomain

/// 不連網路的家庭，記下建立、加入、邀請、移除、離開。
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var stored: Household?
    private var failure: RepositoryError?
    private let gate: Gate?
    /// UI 測試的骨架屏要停留夠久(#204):`current()` 先等這麼久(原因見 `InMemoryAccountRepository`)。
    private let loadDelay: Duration?

    public private(set) var createdNames: [String] = []
    public private(set) var joinedCodes: [String] = []
    public private(set) var removedIDs: [UserID] = []
    public private(set) var inviteCount = 0
    public private(set) var leaveCount = 0

    /// 有家庭時回傳的代墊統計(後端一律每位成員一筆)。
    private var storedAdvances: [HouseholdAdvance]

    /// 撥款報銷送出過的內容，依送出順序。
    public private(set) var reimbursements: [Reimbursement] = []

    /// 解除報銷過的明細,依順序。
    public private(set) var unlinkedIDs: [TransactionID] = []

    /// 標記已額外處理送出過的內容(目標成員與明細),依順序。
    public private(set) var markedSettled: [(memberID: UserID, ids: [TransactionID])] = []

    public init(household: Household?, advances: [HouseholdAdvance] = [], gate: Gate? = nil, loadDelay: Duration? = nil) {
        stored = household
        storedAdvances = advances
        self.gate = gate
        self.loadDelay = loadDelay
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
            note: "全家晚餐", amount: Money(250), accountName: "iOS 測試皮夾", accountKind: .cash,
            recordedAt: SampleTransactions.clock(CalendarDay(year: 2026, month: 9, day: 28), 19, 20)
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

    private static func advanceItem(
        _ id: String, _ amount: Int, _ note: String, kind: AdvanceKind = .expense, account: String = "iOS 測試信用卡",
        accountKind: AccountKind = .creditCard, billing: BillingStatus? = .unbilled
    ) -> AdvanceItem {
        AdvanceItem(
            id: TransactionID(id), date: CalendarDay(year: 2026, month: 9, day: 20), category: .dining, note: note,
            amount: Money(Decimal(amount)), accountName: account, accountKind: accountKind, kind: kind,
            billing: accountKind == .creditCard ? billing : nil
        )
    }

    /// 各種狀態都有的代墊(上游 ADR 0027、0029,`-uiTestingAdvanceStates`):待報銷有現金墊付 250、公帳刷退 100(負項)、
    /// 信用卡已出帳 400、信用卡延至下期 300(待報銷 850);已結清有共同基金撥款結清的 600 與已額外處理的 400;累計撥款 800 = 對應 600 + 溢撥 200。
    public static let myAdvanceWithStates = HouseholdAdvance(
        memberID: InMemoryAuthRepository.Member.sample.user.id,
        memberName: InMemoryAuthRepository.Member.sample.user.name,
        totalAdvanced: Money(1950),
        totalReimbursed: Money(800),
        pendingReimbursement: Money(850),
        advanceItems: [
            advanceItem("sample-advance", 250, "全家晚餐", account: "iOS 測試皮夾", accountKind: .cash),
            advanceItem("sample-refund", 100, "公帳刷退", kind: .refund),
            advanceItem("sample-card-billed", 400, "家庭午餐", billing: .billed),
            advanceItem("sample-card-deferred", 300, "家庭交通", billing: .deferred),
        ],
        reimbursementItems: [ReimbursementItem(
            id: TransactionID("sample-reimb-1"), date: CalendarDay(year: 2026, month: 9, day: 25), amount: Money(600),
            note: "撥款報銷家庭晚餐", accountName: "iOS 測試存款"
        )],
        receivingAccounts: [ReceivingAccount(id: SampleAccounts.savings.id, name: SampleAccounts.savings.name, kind: .bank)],
        settledItems: [
            SettledAdvanceItem(item: advanceItem("sample-settled-reimbursed", 600, "家庭晚餐"), settlement: .reimbursed(TransactionID("sample-reimb-1"))),
            SettledAdvanceItem(item: advanceItem("sample-settled-external", 400, "家庭聚餐"), settlement: .handledSeparately),
        ],
        linkedReimbursed: Money(600),
        unlinkedReimbursed: Money(200)
    )

    /// 小美只有一筆公帳退款 300:待報銷是 −300,「公帳待抵扣」,不能撥款報銷。
    public static let meiOffsetAdvance = HouseholdAdvance(
        memberID: UserID("sample-mei"), memberName: "小美", totalAdvanced: .zero, totalReimbursed: .zero,
        pendingReimbursement: Money(-300),
        advanceItems: [advanceItem("sample-mei-refund", 300, "公帳刷退", kind: .refund)],
        reimbursementItems: [],
        receivingAccounts: [ReceivingAccount(id: AccountID("mei-bank"), name: "小美薪轉", kind: .bank)]
    )

    /// 取過幾次代墊統計(帳戶頁的待報銷橫幅只在公帳範圍才取)。
    public private(set) var advancesCallCount = 0

    public func advances() async throws -> [HouseholdAdvance] {
        advancesCallCount += 1
        if let failure { throw failure }
        return stored == nil ? [] : storedAdvances
    }

    /// 公帳退款是負項,支出是正項(上游 ADR 0027)。
    private static func signed(_ item: AdvanceItem) -> Money { item.kind == .refund ? .zero - item.amount : item.amount }

    private static func net(_ items: [AdvanceItem]) -> Money { items.reduce(.zero) { $0 + signed($1) } }

    /// 後端回傳的統計:待報銷是待報銷明細的淨額(可以是負的);已對應撥款額只算共同基金撥款結清的(已額外處理不算);
    /// 溢撥是累計撥款減去已對應撥款額,最小 0。
    private static func rebuilt(
        _ advance: HouseholdAdvance, pending: [AdvanceItem], settled: [SettledAdvanceItem], reimbursed: Money,
        reimbursementItems: [ReimbursementItem]? = nil
    ) -> HouseholdAdvance {
        let linked = settled.filter { if case .reimbursed = $0.settlement { true } else { false } }
            .reduce(Money.zero) { $0 + signed($1.item) }
        return HouseholdAdvance(
            memberID: advance.memberID, memberName: advance.memberName, totalAdvanced: advance.totalAdvanced,
            totalReimbursed: reimbursed, pendingReimbursement: net(pending), advanceItems: pending,
            reimbursementItems: reimbursementItems ?? advance.reimbursementItems, receivingAccounts: advance.receivingAccounts,
            settledItems: settled, linkedReimbursed: linked, unlinkedReimbursed: max(reimbursed - linked, .zero)
        )
    }

    /// 跟後端一樣記下已報銷:勾選的代墊移到已結清明細(對得到這次撥款),待報銷是剩下明細的淨額,並多一筆報銷明細。
    public func reimburse(_ reimbursement: Reimbursement) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        reimbursements.append(reimbursement)
        var name = "成員"
        let reimbursementID = TransactionID("in-memory-reimbursement-\(reimbursements.count)")
        storedAdvances = storedAdvances.map { advance in
            guard advance.memberID == reimbursement.memberID else { return advance }
            name = advance.memberName
            let selected = Set(reimbursement.advanceIDs)
            let moved = advance.advanceItems.filter { selected.contains($0.id) }
            let remaining = advance.advanceItems.filter { !selected.contains($0.id) }
            // 沒有勾選明細(舊資料的手動金額):維持累計代墊減已報銷。
            let item = ReimbursementItem(
                id: reimbursementID, date: reimbursement.date, amount: reimbursement.amount, note: reimbursement.note,
                accountName: "收款帳戶", recordedAt: Date()
            )
            if selected.isEmpty {
                let reimbursed = advance.totalReimbursed + reimbursement.amount
                return HouseholdAdvance(
                    memberID: advance.memberID, memberName: advance.memberName, totalAdvanced: advance.totalAdvanced,
                    totalReimbursed: reimbursed, pendingReimbursement: max(advance.totalAdvanced - reimbursed, .zero),
                    advanceItems: remaining, reimbursementItems: [item] + advance.reimbursementItems,
                    receivingAccounts: advance.receivingAccounts, settledItems: advance.settledItems,
                    linkedReimbursed: advance.linkedReimbursed, unlinkedReimbursed: advance.unlinkedReimbursed + reimbursement.amount
                )
            }
            return Self.rebuilt(
                advance, pending: remaining,
                settled: moved.map { SettledAdvanceItem(item: $0, settlement: .reimbursed(reimbursementID)) } + advance.settledItems,
                reimbursed: advance.totalReimbursed + reimbursement.amount,
                reimbursementItems: [item] + advance.reimbursementItems
            )
        }
        // 後端 `f32ff6c` 的原文(B:handlers/households.ts@f32ff6c:345)。
        return "成功從共同基金撥款報銷 NT$ \(reimbursement.amount.backendText) 給 \(name)！"
    }

    /// 跟後端一樣(上游 ADR 0027):已結清的明細退回待報銷;沒有這筆已結清的明細時拒絕。
    public func unlinkAdvance(_ id: TransactionID) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        guard storedAdvances.contains(where: { $0.settledItems.contains { $0.id == id } }) else {
            throw RepositoryError.rejected("找不到該筆收支明細")
        }
        unlinkedIDs.append(id)
        storedAdvances = storedAdvances.map { advance in
            guard let settled = advance.settledItems.first(where: { $0.id == id }) else { return advance }
            return Self.rebuilt(
                advance, pending: advance.advanceItems + [settled.item], settled: advance.settledItems.filter { $0.id != id },
                reimbursed: advance.totalReimbursed
            )
        }
        return "已成功解除報銷，該筆明細已退回待報銷清單"
    }

    /// 跟後端一樣(上游 `fe90634`):勾選的公帳代墊移出待報銷、不動共同基金;沒勾選時拒絕。
    public func markAdvancesSettled(for memberID: UserID, ids: [TransactionID]) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        guard !ids.isEmpty else { throw RepositoryError.rejected("請至少勾選一筆要標記已額外處理的代墊明細") }
        markedSettled.append((memberID, ids))
        var count = 0
        storedAdvances = storedAdvances.map { advance in
            guard advance.memberID == memberID else { return advance }
            let selected = Set(ids)
            let moved = advance.advanceItems.filter { selected.contains($0.id) }
            count = moved.count
            return Self.rebuilt(
                advance, pending: advance.advanceItems.filter { !selected.contains($0.id) },
                settled: moved.map { SettledAdvanceItem(item: $0, settlement: .handledSeparately) } + advance.settledItems,
                reimbursed: advance.totalReimbursed
            )
        }
        return "已將 \(count) 筆公帳代墊項目移出待報銷清單（標記為已額外處理完成）！"
    }

    /// 「我們家」:小明(就是登入的範例帳號)和小美;`myRole` 是小明的角色(預設家庭管理員)，小美是另一個角色，
    /// 名冊跟 `myRole` 一致。
    public static func sample(
        myRole: HouseholdRole = .admin, advances: [HouseholdAdvance] = [], gate: Gate? = nil, loadDelay: Duration? = nil
    ) -> InMemoryHouseholdRepository {
        let joined = Date(timeIntervalSince1970: 1_790_000_000)
        return InMemoryHouseholdRepository(household: Household(name: "我們家", myRole: myRole, members: [
            me(role: myRole, joinedAt: joined),
            HouseholdMember(
                userID: UserID("sample-mei"), name: "小美", email: "mei@example.com", role: myRole == .admin ? .member : .admin,
                joinedAt: joined.addingTimeInterval(86_400)
            ),
        ]), advances: advances, gate: gate, loadDelay: loadDelay)
    }

    public func current() async throws -> Household? {
        if let loadDelay { try await Task.sleep(for: loadDelay) }
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
