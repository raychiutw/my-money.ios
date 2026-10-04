import Foundation
import MyMoneyDomain

/// 不連網路的週期收支，記下新增、編輯、刪除的內容。
public actor InMemoryRecurringRepository: RecurringRepository {
    private var stored: [RecurringItem]
    private let currentUser: UserID?
    private let gate: Gate?
    private var failure: RepositoryError?
    private var amortizationFailure: RepositoryError?

    public private(set) var createdDrafts: [RecurringDraft] = []
    public private(set) var updatedDrafts: [RecurringItemID: RecurringDraft] = [:]
    public private(set) var deletedIDs: [RecurringItemID] = []

    /// `items(scope:)` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0
    /// 每次查詢帶的視角，用來確認一律明確帶 `scope`。
    public private(set) var requestedItemScopes: [ViewScope] = []
    public private(set) var requestedAmortizationScopes: [ViewScope] = []

    /// `exportCSV` 回傳的內容(UTF-8 加 BOM,跟後端一樣)。
    public static let sampleCSV = Data("\u{FEFF}名稱,類型,金額,週期,扣款/入帳日,帳戶\n".utf8)

    private static let me = InMemoryAuthRepository.Member.sample.user

    /// 房租(每月，家庭公帳)、年繳保費(每年，個人私帳，沒有關聯帳戶)、薪水(每月收入，個人私帳)——都是範例帳號建立的。
    public static let sampleItems = [
        RecurringItem(
            id: RecurringItemID("sample-rent"), name: "房租", type: .expense, amount: Money(12000), cycle: .monthly,
            dayOfCycle: 5, accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
            isShared: true, ownerID: me.id, ownerName: me.name
        ),
        RecurringItem(
            id: RecurringItemID("sample-insurance"), name: "年繳保費", type: .expense, amount: Money(24000), cycle: .annual,
            dayOfCycle: 15, accountID: nil, accountName: nil, ownerID: me.id, ownerName: me.name
        ),
        RecurringItem(
            id: RecurringItemID("sample-salary"), name: "薪水", type: .income, amount: Money(45000), cycle: .monthly,
            dayOfCycle: 25, accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
            ownerID: me.id, ownerName: me.name
        ),
    ]

    /// 家人(小美)建立的家庭公帳項目(`-uiTestingFamilyEntries`):一般成員點不開，家庭管理員改得了。
    public static let meiInternet = RecurringItem(
        id: RecurringItemID("sample-mei-internet"), name: "網路費", type: .expense, amount: Money(899), cycle: .monthly,
        dayOfCycle: 12, accountID: nil, accountName: nil, isShared: true, ownerID: UserID("sample-mei"), ownerName: "小美"
    )

    /// `currentUser`:登入的人，用來判斷視角(「個人私帳」只留自己建立的);不給時所有項目都算自己的。
    /// `gate`:查詢停在這裡直到放行(觀察換視角時舊回應被丟掉)。
    public init(items: [RecurringItem], currentUser: UserID? = nil, gate: Gate? = nil) {
        stored = items
        self.currentUser = currentUser
        self.gate = gate
    }

    public static func sample(includesFamilyEntries: Bool = false) -> InMemoryRecurringRepository {
        InMemoryRecurringRepository(
            items: sampleItems + (includesFamilyEntries ? [meiInternet] : []), currentUser: me.id
        )
    }

    /// 跟後端一樣依視角篩選:全部是我建立的加上家庭公帳;家庭公帳是所有家庭公帳;個人私帳是我建立的個人私帳。
    private func visible(in scope: ViewScope) -> [RecurringItem] {
        func isMine(_ item: RecurringItem) -> Bool {
            currentUser == nil || item.ownerID == nil || item.ownerID == currentUser
        }
        return stored.filter { item in
            switch scope {
            case .all: isMine(item) || item.isShared
            case .household: item.isShared
            case .personal: isMine(item) && !item.isShared
            }
        }
    }

    public func items(scope: ViewScope) async throws -> [RecurringItem] {
        fetchCount += 1
        requestedItemScopes.append(scope)
        await gate?.pass()
        if gate != nil { try Task.checkCancellation() }
        if let failure { throw failure }
        return visible(in: scope)
    }

    /// 跟後端一樣把每一項的每月平均加總(測試用的替身，給 UI 測試在新增、刪除後看到合計改變)。
    public func amortization(scope: ViewScope) async throws -> RecurringAmortization {
        requestedAmortizationScopes.append(scope)
        if let failure = failure ?? amortizationFailure { throw failure }
        let visible = visible(in: scope)
        func total(_ type: TransactionType) -> Money {
            visible.filter { $0.type == type }.reduce(.zero) { $0 + $1.monthlyAmortization }
        }
        return RecurringAmortization(monthlyExpense: total(.expense), monthlyIncome: total(.income))
    }

    public func create(_ draft: RecurringDraft) async throws {
        if let failure { throw failure }
        createdDrafts.append(draft)
        stored.append(Self.item(
            RecurringItemID("in-memory-recurring-\(createdDrafts.count)"), from: draft,
            ownerID: currentUser, ownerName: currentUser == nil ? nil : Self.me.name
        ))
    }

    public func update(_ id: RecurringItemID, with draft: RecurringDraft) async throws {
        if let failure { throw failure }
        updatedDrafts[id] = draft
        stored = stored.map { existing in
            guard existing.id == id else { return existing }
            // 編輯不改歸屬與建立者(後端 PUT 沒帶 is_shared 時沿用原值)。
            return Self.item(id, from: draft, isShared: existing.isShared, ownerID: existing.ownerID, ownerName: existing.ownerName)
        }
    }

    public func delete(_ id: RecurringItemID) async throws {
        if let failure { throw failure }
        deletedIDs.append(id)
        stored.removeAll { $0.id == id }
    }

    public func exportCSV() async throws -> Data {
        if let failure { throw failure }
        return Self.sampleCSV
    }

    /// 後端建立或更新後的項目;帳戶名稱只認得範例的活存帳戶。
    private static func item(
        _ id: RecurringItemID, from draft: RecurringDraft, isShared: Bool = false, ownerID: UserID? = nil, ownerName: String? = nil
    ) -> RecurringItem {
        RecurringItem(
            id: id, name: draft.name, type: draft.type, amount: draft.amount, cycle: draft.cycle, dayOfCycle: draft.dayOfCycle,
            monthOfCycle: draft.monthOfCycle, accountID: draft.accountID,
            accountName: draft.accountID == SampleAccounts.savings.id ? SampleAccounts.savings.name : nil,
            isShared: isShared, ownerID: ownerID, ownerName: ownerName
        )
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 只有每月平均(`amortization()`)以這個錯誤失敗。
    public func failAmortization(with error: RepositoryError) {
        amortizationFailure = error
    }
}
