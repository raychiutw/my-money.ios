import Foundation
import MyMoneyDomain

/// 不連網路的交易紀錄：依起迄日篩選、依 limit / offset 分頁，並記下每一次查詢。
///
/// 視角的篩選是後端的規則，這裡不模擬(ADR-0001:不在 client 端重算規則)。
public actor InMemoryTransactionRepository: TransactionRepository {
    public struct Query: Equatable, Sendable {
        public let from: CalendarDay
        public let to: CalendarDay
        public let scope: ViewScope
        public let limit: Int
        public let offset: Int
    }

    private var stored: [Transaction]
    private var failure: RepositoryError?

    public struct ExportQuery: Equatable, Sendable {
        public let from: CalendarDay
        public let to: CalendarDay

        public init(from: CalendarDay, to: CalendarDay) {
            self.from = from
            self.to = to
        }
    }

    public private(set) var queries: [Query] = []
    public private(set) var createdDrafts: [TransactionDraft] = []
    public private(set) var updatedDrafts: [TransactionID: TransactionDraft] = [:]
    public private(set) var deletedIDs: [TransactionID] = []
    public private(set) var exportQueries: [ExportQuery] = []

    /// `exportCSV` 回傳的內容(UTF-8 加 BOM,跟後端一樣)。
    public static let sampleCSV = Data("\u{FEFF}日期,類型,分類,金額,備註,帳戶\n".utf8)

    public init(transactions: [Transaction]) {
        stored = transactions
    }

    public func transactions(
        from: CalendarDay, to: CalendarDay, scope: ViewScope, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        queries.append(Query(from: from, to: to, scope: scope, limit: limit, offset: offset))
        if let failure { throw failure }
        // 跟後端一樣日期由新到舊;同一天後記的在前。
        let inPeriod = stored.enumerated()
            .filter { from <= $0.element.date && $0.element.date <= to }
            .sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }
            .map(\.element)
        return Array(inPeriod.dropFirst(offset).prefix(limit))
    }

    public func create(_ draft: TransactionDraft) async throws {
        if let failure { throw failure }
        createdDrafts.append(draft)
        stored.append(Transaction(
            id: TransactionID("in-memory-transaction-\(createdDrafts.count)"),
            accountID: draft.accountID,
            accountName: nil,
            type: draft.type,
            category: draft.category,
            amount: draft.amount,
            note: draft.note,
            date: draft.date,
            isShared: draft.isShared,
            recorderName: InMemoryAuthRepository.Member.sample.user.name
        ))
    }

    public func update(_ id: TransactionID, with draft: TransactionDraft) async throws {
        if let failure { throw failure }
        updatedDrafts[id] = draft
        stored = stored.map { transaction in
            guard transaction.id == id else { return transaction }
            return Transaction(
                id: id,
                accountID: draft.accountID,
                accountName: transaction.accountName,
                type: draft.type,
                category: draft.category,
                amount: draft.amount,
                note: draft.note,
                date: draft.date,
                isShared: draft.isShared,
                recorderName: transaction.recorderName
            )
        }
    }

    public func delete(_ id: TransactionID) async throws {
        if let failure { throw failure }
        deletedIDs.append(id)
        stored.removeAll { $0.id == id }
    }

    public func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data {
        exportQueries.append(ExportQuery(from: from, to: to))
        if let failure { throw failure }
        return Self.sampleCSV
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }
}

/// 畫面 model 測試與 UI 測試共用的交易紀錄。日期相對於「今天」,UI 測試在任何一天跑都落在本月。
public enum SampleTransactions {
    /// 以台灣時間的今天產生(給 `-uiTesting` 的 composition root 用)。
    public static func makeForToday() -> [Transaction] {
        make(today: CalendarDay.today())
    }

    public static func make(today: CalendarDay) -> [Transaction] {
        let first = today.firstOfMonth
        let tenth = min(today, CalendarDay(year: today.year, month: today.month, day: 10))
        return [
            transaction("sample-income", .income, .salary, 45000, "", first, shared: true, account: SampleAccounts.savings),
            transaction("sample-repayment", .expense, .creditCardRepayment, 5000, "繳納【iOS 測試信用卡】卡費", tenth,
                        shared: true, account: SampleAccounts.savings),
            transaction("sample-lunch", .expense, .dining, 120, "午餐", today, shared: true, account: SampleAccounts.savings),
            transaction("sample-headphones", .expense, TransactionCategory("購物"), 880, "耳機", today, shared: false,
                        accountName: SampleAccounts.card.name, accountID: SampleAccounts.card.id),
        ]
    }

    private static func transaction(
        _ id: String,
        _ type: TransactionType,
        _ category: TransactionCategory,
        _ amount: Int,
        _ note: String,
        _ date: CalendarDay,
        shared: Bool,
        account: BankAccount
    ) -> Transaction {
        transaction(id, type, category, amount, note, date, shared: shared, accountName: account.name, accountID: account.id)
    }

    private static func transaction(
        _ id: String,
        _ type: TransactionType,
        _ category: TransactionCategory,
        _ amount: Int,
        _ note: String,
        _ date: CalendarDay,
        shared: Bool,
        accountName: String,
        accountID: AccountID
    ) -> Transaction {
        Transaction(
            id: TransactionID(id),
            accountID: accountID,
            accountName: accountName,
            type: type,
            category: category,
            amount: Money(Decimal(amount)),
            note: note,
            date: date,
            isShared: shared,
            recorderName: InMemoryAuthRepository.Member.sample.user.name
        )
    }
}
