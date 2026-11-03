import Foundation

/// 交易記錄(`/transactions`)。
public protocol TransactionRepository: Sendable {
    /// 一頁收支明細，順序照後端(日期由新到舊)。起日或迄日是 `nil` 時不限;`accountID` 是 `nil` 時不限帳戶(上游 ADR 0019)。
    func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, accountID: AccountID?, limit: Int, offset: Int
    ) async throws -> [Transaction]

    /// 後端篩選的一頁(上游 `b06d17c`、ADR 0035、#184):`cursor` 是上一頁回傳的 `nextCursor`(第一頁是 `nil`);
    /// 篩選(視角、起迄日、帳戶、分類、類型、關鍵字)全部由後端做,順序日期由新到舊。
    func page(_ query: TransactionQuery, cursor: String?, limit: Int) async throws -> TransactionPage

    /// 同樣篩選下的全量統計(`GET /transactions/summary/range`):總收入、總支出、筆數與每日小計,系統分類也算。
    func rangeSummary(_ query: TransactionQuery) async throws -> RangeSummary

    func create(_ draft: TransactionDraft) async throws

    /// 家人記的也能編輯。「信用卡還款」的紀錄後端會拒絕(400)。
    func update(_ id: TransactionID, with draft: TransactionDraft) async throws

    /// 「信用卡還款」的紀錄後端會拒絕(400)。
    func delete(_ id: TransactionID) async throws

    /// 起迄日內我記的交易記錄的 CSV(`GET /export/csv`,UTF-8 加 BOM),原樣回傳。
    func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data
}

extension TransactionRepository {
    /// 不指定帳戶的一頁收支明細。
    public func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        try await transactions(from: from, to: to, scope: scope, accountID: nil, limit: limit, offset: offset)
    }

    /// 區間內的所有交易記錄：用 limit / offset 一路抓到回傳筆數少於一頁為止。
    public func allTransactions(
        from: CalendarDay, to: CalendarDay, scope: ViewScope, accountID: AccountID? = nil, pageSize: Int = 200
    ) async throws -> [Transaction] {
        var all: [Transaction] = []
        var offset = 0
        while true {
            let page = try await transactions(
                from: from, to: to, scope: scope, accountID: accountID, limit: pageSize, offset: offset
            )
            all += page
            guard page.count == pageSize else { return all }
            offset += pageSize
        }
    }
}

/// 收支明細的後端篩選條件。`nil` 的欄位不送、不限。
public struct TransactionQuery: Equatable, Sendable {
    public var scope: ViewScope
    public var from: CalendarDay?
    public var to: CalendarDay?
    public var accountID: AccountID?
    public var category: TransactionCategory?
    public var type: TransactionType?
    /// 關鍵字:不分大小寫,後端比對備註、分類、帳戶名稱與記帳人名稱;空白(只有空白字元)當作沒有。
    public var keyword: String?

    public init(
        scope: ViewScope = .all, from: CalendarDay? = nil, to: CalendarDay? = nil, accountID: AccountID? = nil,
        category: TransactionCategory? = nil, type: TransactionType? = nil, keyword: String? = nil
    ) {
        self.scope = scope
        self.from = from
        self.to = to
        self.accountID = accountID
        self.category = category
        self.type = type
        self.keyword = keyword
    }
}

/// 一頁收支明細與下一頁的游標(沒有下一頁是 `nil`)。
public struct TransactionPage: Sendable {
    public let transactions: [Transaction]
    public let nextCursor: String?

    public init(transactions: [Transaction], nextCursor: String?) {
        self.transactions = transactions
        self.nextCursor = nextCursor
    }
}

/// 區間統計(上游 `GET /transactions/summary/range`):全量加總,信用卡還款、內部轉帳、ATM 提款、公帳代墊報銷也算。
public struct RangeSummary: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: CalendarDay
        public let income: Money
        public let expense: Money

        public init(date: CalendarDay, income: Money, expense: Money) {
            self.date = date
            self.income = income
            self.expense = expense
        }
    }

    public let totalIncome: Money
    public let totalExpense: Money
    public let count: Int
    /// 每日小計,日期由新到舊。
    public let byDay: [Day]

    public init(totalIncome: Money, totalExpense: Money, count: Int, byDay: [Day]) {
        self.totalIncome = totalIncome
        self.totalExpense = totalExpense
        self.count = count
        self.byDay = byDay
    }

    public static let empty = RangeSummary(totalIncome: .zero, totalExpense: .zero, count: 0, byDay: [])
}
