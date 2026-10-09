import Foundation
import MyMoneyDomain

/// 不連網路的收支明細：依起迄日篩選、依 limit / offset 分頁，並記下每一次查詢。
///
/// 視角的篩選是後端的規則，這裡不模擬(ADR-0001:不在 client 端重算規則)。
public actor InMemoryTransactionRepository: TransactionRepository {
    /// UI 測試的骨架屏要停留夠久(#204 核對):查詢先等這麼久(每次查詢各自 sleep,不用 `Gate`)。
    private var loadDelay: Duration?

    public func setLoadDelay(_ delay: Duration?) {
        loadDelay = delay
    }

    public struct Query: Equatable, Sendable {
        public let from: CalendarDay?
        public let to: CalendarDay?
        public let scope: ViewScope
        public let accountID: AccountID?
        public let limit: Int
        public let offset: Int
    }

    private var stored: [Transaction]
    private var failure: RepositoryError?
    private var nextQueryGate: Gate?

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

    /// 下一次查詢停在 `gate`,直到測試放行;之後的查詢照常回應。用來重現「舊的查詢比新的晚回來」。
    public func holdNextQuery(at gate: Gate) {
        nextQueryGate = gate
    }

    public func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, accountID: AccountID?, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        if let loadDelay { try await Task.sleep(for: loadDelay) }
        queries.append(Query(from: from, to: to, scope: scope, accountID: accountID, limit: limit, offset: offset))
        if let gate = nextQueryGate {
            nextQueryGate = nil
            await gate.pass()
        }
        if let failure { throw failure }
        // 跟後端一樣日期由新到舊;同一天後記的在前。
        let inPeriod = stored.enumerated()
            .filter { item in
                (from.map { $0 <= item.element.date } ?? true) && (to.map { item.element.date <= $0 } ?? true)
                    // 帳戶篩選是後端的規則(上游 ADR 0019):只回這個帳戶的收支明細。
                    && (accountID.map { $0 == item.element.accountID } ?? true)
            }
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
            recorderName: InMemoryAuthRepository.Member.sample.user.name,
            recorderID: InMemoryAuthRepository.Member.sample.user.id,
            billing: draft.defersToNextStatement ? .deferred : .unbilled,
            // 跟後端一樣:建立當下自動記下時間(使用者只選日期,上游 718ace9、#207)。
            recordedAt: Date()
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
                recorderName: transaction.recorderName,
                recorderID: transaction.recorderID,
                billing: draft.defersToNextStatement ? .deferred : transaction.billing,
                // 跟後端一樣:編輯收支保留原建立時間。
                recordedAt: transaction.recordedAt
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

    /// 每個月的收入與支出，不含「信用卡還款」,跟後端的收支趨勢一樣(給 UI 測試用的統計替身;不模擬視角)。
    public func monthlySummaries(year: Int) -> [MonthlySummary] {
        let byMonth = Dictionary(grouping: stored.filter { $0.date.year == year && !$0.isSystemRecord }) {
            CalendarMonth($0.date)
        }
        return byMonth.keys.sorted().map { month in
            let items = byMonth[month] ?? []
            func total(_ type: TransactionType) -> Money {
                items.filter { $0.type == type }.reduce(.zero) { $0 + $1.amount }
            }
            return MonthlySummary(month: month, income: total(.income), expense: total(.expense))
        }
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }
}

/// 畫面 model 測試與 UI 測試共用的收支明細。日期相對於「今天」,UI 測試在任何一天跑都落在本月。
public enum SampleTransactions {
    /// 以台灣時間的今天產生(給 `-uiTesting` 的 composition root 用)。
    public static func makeForToday(includeFamilyEntries: Bool = false, includeCardBilling: Bool = false) -> [Transaction] {
        make(today: CalendarDay.today(), includeFamilyEntries: includeFamilyEntries, includeCardBilling: includeCardBilling)
    }

    /// `includeFamilyEntries`:多兩筆「家庭公帳、家人(小美)記的」交易，一筆名稱短、一筆備註很長(交易列版型的 UI 測試，#128)。
    /// `includeCardBilling`:信用卡多兩筆消費，一筆「已出帳」、一筆「延至下期」(收支明細列的帳單狀態標籤，#188)。
    public static func make(today: CalendarDay, includeFamilyEntries: Bool = false, includeCardBilling: Bool = false) -> [Transaction] {
        let first = today.firstOfMonth
        let tenth = min(today, CalendarDay(year: today.year, month: today.month, day: 10))
        let family: [Transaction] = includeFamilyEntries
            ? [
                familyTransaction("family-short", "晚餐-水煎包", 85, today),
                familyTransaction("family-long", "週末全家一起去大賣場採買下週要用的食材和日用品還有小孩的文具", 2380, today),
            ]
            : []
        let cardBilling: [Transaction] = includeCardBilling
            ? [
                cardTransaction("card-billed", "上期晚餐", 640, first, .billed),
                cardTransaction("card-deferred", "延遲請款的機票", 5200, today, .deferred),
            ]
            : []
        return family + cardBilling + [
            transaction("sample-income", .income, .salary, 45000, "", first, shared: true, account: SampleAccounts.savings),
            transaction("sample-repayment", .expense, .creditCardRepayment, 5000, "繳納【iOS 測試信用卡】卡費", tenth,
                        shared: true, account: SampleAccounts.savings),
            transaction("sample-lunch", .expense, .dining, 120, "午餐", today, shared: true, account: SampleAccounts.savings),
            transaction("sample-headphones", .expense, TransactionCategory("購物"), 880, "耳機", today, shared: false,
                        accountName: SampleAccounts.card.name, accountID: SampleAccounts.card.id),
        ]
    }

    /// 信用卡的個人私帳消費，帶帳單狀態。
    private static func cardTransaction(
        _ id: String, _ note: String, _ amount: Int, _ date: CalendarDay, _ billing: BillingStatus
    ) -> Transaction {
        Transaction(
            id: TransactionID(id), accountID: SampleAccounts.card.id, accountName: SampleAccounts.card.name, type: .expense,
            category: TransactionCategory("購物"), amount: Money(Decimal(amount)), note: note, date: date, isShared: false,
            recorderName: InMemoryAuthRepository.Member.sample.user.name, recorderID: InMemoryAuthRepository.Member.sample.user.id,
            billing: billing, recordedAt: clock(date, 13, 5)
        )
    }

    /// 家庭公帳、小美記的支出。
    private static func familyTransaction(_ id: String, _ note: String, _ amount: Int, _ date: CalendarDay) -> Transaction {
        Transaction(
            id: TransactionID(id), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: .expense,
            category: .dining, amount: Money(Decimal(amount)), note: note, date: date, isShared: true, recorderName: "小美",
            recorderID: UserID("sample-mei"), recordedAt: clock(date, 9, 41)
        )
    }

    /// 台灣時間某天的幾點幾分(範例收支的記錄時間)。
    static func clock(_ day: CalendarDay, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarDay.timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)) ?? Date()
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
            recorderName: InMemoryAuthRepository.Member.sample.user.name,
            recorderID: InMemoryAuthRepository.Member.sample.user.id,
            recordedAt: clock(date, 12, 30)
        )
    }
}
