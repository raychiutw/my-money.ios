import Foundation
import MyMoneyDomain

/// 不連網路的週期收支，記下新增、編輯、刪除的內容。
public actor InMemoryRecurringRepository: RecurringRepository {
    private var stored: [RecurringItem]
    private var failure: RepositoryError?
    private var amortizationFailure: RepositoryError?

    public private(set) var createdDrafts: [RecurringDraft] = []
    public private(set) var updatedDrafts: [RecurringItemID: RecurringDraft] = [:]
    public private(set) var deletedIDs: [RecurringItemID] = []

    /// `items()` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    /// `exportCSV` 回傳的內容(UTF-8 加 BOM,跟後端一樣)。
    public static let sampleCSV = Data("\u{FEFF}名稱,類型,金額,週期,扣款/入帳日,帳戶\n".utf8)

    /// 房租(每月)、年繳保費(每年，沒有關聯帳戶)、薪水(每月收入)。
    public static let sampleItems = [
        RecurringItem(
            id: RecurringItemID("sample-rent"), name: "房租", type: .expense, amount: Money(12000), cycle: .monthly,
            dayOfCycle: 5, accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name
        ),
        RecurringItem(
            id: RecurringItemID("sample-insurance"), name: "年繳保費", type: .expense, amount: Money(24000), cycle: .annual,
            dayOfCycle: 15, accountID: nil, accountName: nil
        ),
        RecurringItem(
            id: RecurringItemID("sample-salary"), name: "薪水", type: .income, amount: Money(45000), cycle: .monthly,
            dayOfCycle: 25, accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name
        ),
    ]

    public init(items: [RecurringItem]) {
        stored = items
    }

    public static func sample() -> InMemoryRecurringRepository {
        InMemoryRecurringRepository(items: sampleItems)
    }

    public func items() async throws -> [RecurringItem] {
        fetchCount += 1
        if let failure { throw failure }
        return stored
    }

    /// 跟後端一樣把每一項的分攤平滑加總(測試用的替身，給 UI 測試在新增、刪除後看到合計改變)。
    public func amortization() async throws -> RecurringAmortization {
        if let failure = failure ?? amortizationFailure { throw failure }
        func total(_ type: TransactionType) -> Money {
            stored.filter { $0.type == type }.reduce(.zero) { $0 + $1.monthlyAmortization }
        }
        return RecurringAmortization(monthlyExpense: total(.expense), monthlyIncome: total(.income))
    }

    public func create(_ draft: RecurringDraft) async throws {
        if let failure { throw failure }
        createdDrafts.append(draft)
        stored.append(Self.item(RecurringItemID("in-memory-recurring-\(createdDrafts.count)"), from: draft))
    }

    public func update(_ id: RecurringItemID, with draft: RecurringDraft) async throws {
        if let failure { throw failure }
        updatedDrafts[id] = draft
        stored = stored.map { $0.id == id ? Self.item(id, from: draft) : $0 }
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

    /// 後端建立或更新後的項目;帳戶名稱只認得範例的銀行存款帳戶。
    private static func item(_ id: RecurringItemID, from draft: RecurringDraft) -> RecurringItem {
        RecurringItem(
            id: id, name: draft.name, type: draft.type, amount: draft.amount, cycle: draft.cycle, dayOfCycle: draft.dayOfCycle,
            accountID: draft.accountID,
            accountName: draft.accountID == SampleAccounts.savings.id ? SampleAccounts.savings.name : nil
        )
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 只有分攤平滑(`amortization()`)以這個錯誤失敗。
    public func failAmortization(with error: RepositoryError) {
        amortizationFailure = error
    }
}
