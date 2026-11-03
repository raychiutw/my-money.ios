import Foundation
import MyMoneyDomain
import Observation

/// 交易頁的一天：當天的交易記錄，以及當日的收入與支出(不含信用卡還款)。
public struct TransactionDay: Identifiable, Sendable {
    public let date: CalendarDay
    /// 分組標頭的日期，例如「9月29日週二」(DESIGN.md「日期」)。
    public let title: String
    public let transactions: [Transaction]
    public let income: Money
    public let expense: Money

    public var id: CalendarDay { date }

    /// 當日淨額(收入減支出，系統分類也算，#118、#238)。
    public var net: Money { income - expense }

    /// 當天有收入或支出才有淨額可以顯示(系統分類也算，所以只有完全沒有收支的天沒有)。
    public var hasNet: Bool { income > .zero || expense > .zero }

    /// 日標頭右邊的淨額，帶正負號，例如「+$45,000」「−$1,000」;零是「$0」。
    public var netText: String { net.signedFormatted() }
}

/// 交易頁的 model(parity.md「交易」)。
///
/// 每頁 20 筆,捲到底載入下一頁(上游 `b06d17c`、ADR 0035、#184,#317);視角、起迄日、帳戶、類型、分類、關鍵字全部送到後端查詢,
/// 總收入、總支出、筆數與每日小計也是後端的區間統計(全量加總),手機上不再對整個月重算。
/// 視角、起迄日、類型、分類在篩選 sheet 裡改一份草稿，按「完成」才套用(#74);關鍵字停手之後才查詢(`search()`)。
@MainActor
@Observable
public final class TransactionsModel: Alerting {
    public typealias Phase = LoadPhase

    /// 類型篩選(送到後端)。
    public enum TypeFilter: Hashable, Sendable {
        case all
        case expense
        case income
    }

    /// 目前套用的篩選。預設是全部視角、本月 1 號到今天(台灣時間)、全部類型、全部分類。
    public private(set) var filter: Filter

    /// 篩選 sheet 編輯中的草稿;按「完成」才套用。
    public var filterDraft: Filter

    /// 篩選 sheet 開著。
    public var isEditingFilter = false

    /// 篩選 sheet 裡「帳戶」的選項:隨草稿的視角連動(上游 ADR 0019 §3)——全部列所有可用帳戶，家庭公帳列家庭共同基金帳戶與有家庭代墊的卡，
    /// 個人私帳只列個人帳戶。由 `refreshFilterAccountOptions()` 載入。
    public private(set) var filterAccountOptions: [AccountChoice] = []

    /// 關鍵字：不分大小寫，比對備註、分類、帳戶名稱與記帳人。
    public var keyword = ""

    public private(set) var phase: Phase = .loading

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    public let deleteConfirmation = "確定要刪除這筆\(Terms.transactions)嗎？"

    /// 每頁筆數。
    static let pageSize = 20

    /// 已載入的頁(後端已依篩選過濾,日期由新到舊)。
    private var loaded: [Transaction] = []

    /// 目前篩選下的全量統計(後端 `summary/range`):總額、筆數、每日小計。
    private var summary: RangeSummary = .empty

    /// 下一頁的游標;沒有下一頁是 `nil`。
    private var nextCursor: String?

    /// 正在載入下一頁。
    public private(set) var isLoadingMore = false

    /// 最近一次載入成功的查詢條件;`search()` 用它判斷關鍵字有沒有變。
    @ObservationIgnored private var loadedQuery: TransactionQuery?

    /// 每次重新載入遞增:舊的查詢或下一頁比較晚回來時丟掉。
    @ObservationIgnored private var loadToken = 0

    @ObservationIgnored private let repository: any TransactionRepository
    @ObservationIgnored private let accountRepository: (any AccountRepository)?
    @ObservationIgnored private let context: SessionContext
    public var dataVersion: DataVersion { context.dataVersion }
    private var today: () -> CalendarDay { context.today }
    @ObservationIgnored private let currentUser: UserID?
    /// 編輯與刪除的權限(上游 ADR 0013、#133);沒有就不擋，交給後端。
    @ObservationIgnored private let permissions: PermissionsModel?
    private var locale: Locale { context.locale }
    private var defaults: UserDefaults { context.defaults }
    @ObservationIgnored private var freshness = LoadFreshness<Unscoped>()

    /// 畫面的 `.task(id:)` 與 `refreshIfStale()` 共用的重載鍵:資料版本變了就要重載。
    public var reloadKey: ReloadKey<Unscoped> { ReloadKey(version: dataVersion.value) }

    /// 骨架屏每天的列數(#204 核對):上次載入完成時前三天各有幾筆(每天最多 4);第一次沒有記錄時兩天、3 與 2 筆。
    public var skeletonDayRows: [Int] {
        let stored = defaults.array(forKey: "skeleton.transactions.dayRows") as? [Int]
        return (stored?.isEmpty == false ? stored : nil) ?? [3, 2]
    }

    /// `currentUser` 是登入的人：自己記的交易記錄不顯示記帳人。`locale` 決定日期的格式，預設跟著系統。
    public init(
        repository: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        currentUser: UserID? = nil,
        permissions: PermissionsModel? = nil,
        context: SessionContext
    ) {
        self.repository = repository
        accountRepository = accounts
        self.context = context
        self.currentUser = currentUser
        self.permissions = permissions
        let now = context.today()
        let thisMonth = Filter(from: now.firstOfMonth, to: now)
        filter = thisMonth
        filterDraft = thisMonth
    }

    /// 個別參數的寫法(測試與預覽用),轉成 `SessionContext`。
    public convenience init(
        repository: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        dataVersion: DataVersion,
        currentUser: UserID? = nil,
        permissions: PermissionsModel? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.init(
            repository: repository, accounts: accounts, currentUser: currentUser, permissions: permissions,
            context: SessionContext(dataVersion: dataVersion, defaults: defaults, locale: locale, today: today)
        )
    }

    /// 打開篩選 sheet:草稿從目前套用的篩選開始。
    public func editFilter() {
        filterDraft = filter
        isEditingFilter = true
    }

    /// 依草稿的視角載入帳戶選項;原本選的帳戶不在新視角的範圍就重設為「全部帳戶」(`nil`)。篩選 sheet 開著、視角改變時呼叫。
    public func refreshFilterAccountOptions() async {
        let scope = filterDraft.scope
        guard let accountRepository else {
            filterAccountOptions = []
            return
        }
        guard let accounts = try? await accountRepository.accounts(scope: AccountScope(scope)) else { return }
        // 載入期間又換了視角:這份結果過期了，不套用。
        guard scope == filterDraft.scope else { return }
        filterAccountOptions = accounts.map { AccountChoice(id: $0.id, name: $0.name) }
        if let selected = filterDraft.account, !filterAccountOptions.contains(selected) {
            filterDraft.account = nil
        }
    }

    /// 以指定帳戶開啟記帳頁(給首頁帳戶卡用):本月、全部視角、全部類型與分類，加上該帳戶的篩選。
    public func showAccount(_ account: AccountChoice) async {
        let now = today()
        var next = Filter(from: now.firstOfMonth, to: now)
        next.account = account
        filter = next
        filterDraft = next
        keyword = ""
        await load()
    }

    /// 按「完成」:套用草稿。任何一項篩選改了才重新查詢(從第一頁重來),而且只查詢一次。
    public func applyFilter() async {
        isEditingFilter = false
        let needsQuery = filterDraft != filter
        filter = filterDraft
        if needsQuery {
            await load()
        }
    }

    /// 「重設為本月」:草稿的起迄日改回本月 1 號到今天(台灣時間);視角、類型、分類不變。
    public func resetFilterDraftToThisMonth() {
        let now = today()
        filterDraft.from = now.firstOfMonth
        filterDraft.to = now
    }

    /// 按「取消」:丟掉草稿，篩選不變，也不查詢。往下滑關掉 sheet 也一樣。
    public func cancelFilter() {
        isEditingFilter = false
    }

    // MARK: 年月快速切換(#130)

    /// 今天所在的月份(台灣時間)，也是年月控制項能切到的最後一個月。
    public var currentMonth: CalendarMonth { CalendarMonth(today()) }

    /// 整月的範圍:本月是 1 號到今天，過去的月份是 1 號到月底(台灣時間)。
    private func range(of month: CalendarMonth) -> (from: CalendarDay, to: CalendarDay) {
        let first = CalendarDay(year: month.year, month: month.month, day: 1)
        let last = month == currentMonth ? today() : CalendarDay(year: month.year, month: month.month, day: first.daysInMonth)
        return (first, last)
    }

    /// 目前篩選剛好是某個整月時是那個月;在篩選 sheet 設了自訂範圍就是 `nil`。
    public var selectedMonth: CalendarMonth? {
        let month = CalendarMonth(filter.from)
        let whole = range(of: month)
        return filter.from == whole.from && filter.to == whole.to ? month : nil
    }

    /// 年月控制項的標題，例如「2026年9月」;自訂範圍時是範圍文字「9月10日–9月20日」。
    public var monthTitle: String {
        if let month = selectedMonth { return month.text(locale: locale) }
        let today = today()
        return "\(filter.from.text(today: today, locale: locale))–\(filter.to.text(today: today, locale: locale))"
    }

    /// 上一月、下一月的基準:整月就是那個月，自訂範圍從迄日所在的月份算。
    private var baseMonth: CalendarMonth { selectedMonth ?? CalendarMonth(filter.to) }

    /// 不能切到未來的月份。
    public var canGoToNextMonth: Bool { baseMonth < currentMonth }

    public func goToPreviousMonth() async {
        await selectMonth(baseMonth.previous)
    }

    public func goToNextMonth() async {
        guard canGoToNextMonth else { return }
        await selectMonth(baseMonth.next)
    }

    /// 切到某個整月:等同改篩選的起迄日，視角、類型、分類不變(關鍵字本來就不在篩選裡)，並重新查詢。
    /// 未來的月份、或已經是那個月，什麼都不做。篩選 sheet 打開時草稿本來就從目前的篩選開始(`editFilter`)，兩邊永遠一致。
    public func selectMonth(_ month: CalendarMonth) async {
        guard month <= currentMonth else { return }
        let whole = range(of: month)
        guard filter.from != whole.from || filter.to != whole.to else { return }
        var next = filter
        next.from = whole.from
        next.to = whole.to
        filter = next
        await load()
    }

    /// 套用了非預設的篩選:視角不是全部、起迄日不是「本月 1 號到今天」、類型或分類不是全部，或搜尋關鍵字不是空白。
    /// 篩選按鈕這時改用實心圖示，畫面上雖然沒有範圍文字，也不會把篩選過的結果當成全部(#107)。
    public var isFilterActive: Bool {
        let now = today()
        let isDefault = filter == Filter(from: now.firstOfMonth, to: now)
        return !isDefault || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 目前套用的篩選的一句話描述，例如「家庭公帳・9月1日–9月30日・支出・餐飲」;預設時是「全部・9月1日–9月29日」。
    /// 畫面上不再顯示(tab 首頁沒有標題與副標題，#108),只當篩選按鈕的 VoiceOver 值。日期用系統格式(DESIGN.md「日期」)。
    public var filterSummary: String {
        let today = today()
        var parts = [
            filter.scope.title,
            "\(filter.from.text(today: today, locale: locale))–\(filter.to.text(today: today, locale: locale))",
        ]
        if let account = filter.account {
            parts.append(account.name)
        }
        switch filter.type {
        case .all: break
        case .expense: parts.append("支出")
        case .income: parts.append("收入")
        }
        if let category = filter.category {
            parts.append(category.name)
        }
        return parts.joined(separator: "・")
    }

    /// 篩選後的交易記錄，依日期分組，新的在前。
    public var days: [TransactionDay] {
        var order: [CalendarDay] = []
        var byDay: [CalendarDay: [Transaction]] = [:]
        let totals = Dictionary(summary.byDay.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        for transaction in loaded {
            if byDay[transaction.date] == nil { order.append(transaction.date) }
            byDay[transaction.date, default: []].append(transaction)
        }
        let today = today()
        return order.sorted(by: >).map { date in
            let items = byDay[date] ?? []
            // 當日小計用後端的整天統計:最底下那一天只載入一半時也是準確的;沒有統計時退回已載入的列。
            let total = totals[date]
            return TransactionDay(
                date: date, title: date.headerText(today: today, locale: locale), transactions: items,
                income: total?.income ?? Self.income(of: items), expense: total?.expense ?? Self.expense(of: items)
            )
        }
    }

    /// 總筆數、總收入、總支出:後端的區間統計(符合目前篩選的整個範圍,不是已載入的頁)。
    public var count: Int { summary.count }
    public var totalIncome: Money { summary.totalIncome }
    /// 總收入、總支出、每日小計全量加總(上游 a09e923「收支正負號全量直觀加總」，parity 第 26 項已與上游對齊，#238)。
    public var totalExpense: Money { summary.totalExpense }
    public var net: Money { totalIncome - totalExpense }

    /// 今天(台灣時間)與地區:`TransactionsModel+Numbers` 的日期文字用。
    var todayValue: CalendarDay { today() }
    var localeValue: Locale { locale }

    /// 每日統計(後端 `by_day`):長條圖用。
    var dailySummary: [RangeSummary.Day] { summary.byDay }

    /// 送到後端的篩選條件:關鍵字去前後空白,空白當作沒有。
    private var currentQuery: TransactionQuery {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return TransactionQuery(
            scope: filter.scope, from: filter.from, to: filter.to, accountID: filter.account?.id, category: filter.category,
            type: { switch filter.type { case .all: nil; case .expense: .expense; case .income: .income } }(),
            keyword: word.isEmpty ? nil : word
        )
    }

    /// 依目前套用的篩選從第一頁重新載入:第一頁 20 筆與整個範圍的統計同時查詢。
    public func load() async {
        let key = reloadKey
        let query = currentQuery
        loadToken += 1
        let token = loadToken
        do {
            async let first = repository.page(query, cursor: nil, limit: Self.pageSize)
            async let totals = repository.rangeSummary(query)
            let (page, range) = try await (first, totals)
            // 篩選、關鍵字和第一次載入各自是一個 Task,舊的查詢可能比較晚回來:已經重新載入過就丟掉。
            guard token == loadToken else { return }
            loaded = page.transactions
            summary = range
            nextCursor = page.nextCursor
            loadedQuery = query
            freshness.markLoaded(key)
            defaults.set(days.prefix(3).map { min($0.transactions.count, 4) }, forKey: "skeleton.transactions.dayRows")
            phase = .loaded
            await permissions?.loadIfNeeded()
        } catch {
            guard token == loadToken else { return }
            phase = .failure(error)
        }
    }

    /// 已載入的筆數(畫面用它判斷「載入更多」那一列是不是還在畫面上要接著載)。
    public var loadedCount: Int { loaded.count }

    /// 還有下一頁(捲到底會載入)。
    public var canLoadMore: Bool { nextCursor != nil }

    /// 載入下一頁,接在已載入的後面。失敗顯示訊息、已載入的留著,可以再試;條件改了(重新載入過)的舊回應丟掉。
    public func loadMore() async {
        guard let cursor = nextCursor, let query = loadedQuery, !isLoadingMore else { return }
        let token = loadToken
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.page(query, cursor: cursor, limit: Self.pageSize)
            guard token == loadToken else { return }
            let known = Set(loaded.map(\.id))
            loaded += page.transactions.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            guard token == loadToken else { return }
            alertMessage = error.localizedDescription
        }
    }

    /// 關鍵字改了(畫面停手之後呼叫):送給後端、從第一頁重載;跟上一次載入的關鍵字相同(包含都是空白)就不查詢。
    public func search() async {
        guard currentQuery.keyword != loadedQuery?.keyword else { return }
        await load()
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard freshness.isStale(reloadKey) else { return }
        await load()
    }

    /// 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷)是系統成對產生的紀錄:上游 ADR 0031 起可以編輯(只改金額、日期、備註)與刪除(成對刪除);
    /// 後端沒辦法唯一配對的舊紀錄會拒絕(400,訊息照顯示)。權限見 `EditingPermissions.canModify`(上游 ADR 0013、#133)。
    public func canModify(_ transaction: Transaction) -> Bool {
        permissions?.current.canModify(transaction) ?? true
    }

    /// 點不開的列為什麼不能編輯(點一下跳出的說明);可以改的是 `nil`。
    public func lockReason(for transaction: Transaction) -> String? {
        if canModify(transaction) { return nil }
        if transaction.isSystemRecord { return "系統紀錄，僅記錄者本人或家庭管理員可以編輯、刪除" }
        return transaction.isShared ? "他人記錄的\(OwnershipName.household)，僅記錄者或家庭管理員可以編輯、刪除" : "他人的\(OwnershipName.personal)，僅記錄者本人可以編輯、刪除"
    }

    /// 說明 alert 的標題(#146)。
    public let lockAlertTitle = "不能編輯這筆\(Terms.transactions)"

    /// 點不開的列的 VoiceOver 提示;原因不再塞在整句最後，點了才跳出說明(#146)。可以改的是 `nil`。
    public func lockHint(for transaction: Transaction) -> String? {
        lockReason(for: transaction) == nil ? nil : "點兩下查看為什麼不能編輯"
    }

    /// 一列收支明細要呈現的全部內容(#208 第 5 項):視角是目前登入的人。
    public func content(of transaction: Transaction) -> TransactionRowContent {
        TransactionRowContent(transaction, viewer: currentUser)
    }

    public func makeEditor(for transaction: Transaction) -> TransactionEditorModel? {
        guard canModify(transaction), let accountRepository else { return nil }
        return TransactionEditorModel(
            editing: transaction, transactions: repository, accounts: accountRepository, dataVersion: dataVersion
        )
    }

    /// 刪除;成功後遞增資料版本。家人記的也能刪除。
    public func delete(_ transaction: Transaction) async {
        guard canModify(transaction) else { return }
        _ = await commit(dataVersion) { try await repository.delete(transaction.id) }
    }

    /// 目前起迄日的 CSV,檔名跟 web 一樣是 `my-money-今天.csv`。
    public func csvExport() -> CSVExport {
        let repository = repository
        let (from, to) = (filter.from, filter.to)
        return CSVExport(fileName: "my-money-\(today().iso).csv") {
            try await repository.exportCSV(from: from, to: to)
        }
    }

    /// 收入合計:所有正項(`income`)，不隱藏任何分類——畫面上看得到的每一筆列都算進來，加總才對得上(上游 a09e923)。
    static func income(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .income }.reduce(.zero) { $0 + $1.amount }
    }

    /// 支出合計:所有負項(`expense`)，含信用卡還款、轉帳、ATM 提款、報銷(上游 a09e923)。
    static func expense(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .expense }.reduce(.zero) { $0 + $1.amount }
    }
}

extension TransactionsModel {
    /// 交易頁的篩選，也是篩選 sheet 的草稿。全部送到後端查詢(上游 ADR 0035)。
    public struct Filter: Equatable, Sendable {
        public var scope: ViewScope = .all

        /// 起日;改到迄日之後時，迄日跟著改成起日(迄日不早於起日)。
        public var from: CalendarDay {
            didSet {
                if to < from {
                    to = from
                }
            }
        }

        public var to: CalendarDay

        /// 換類型時，不屬於新類型的分類篩選會清掉。
        public var type: TypeFilter = .all {
            didSet {
                if let category, !categoryOptions.contains(category) {
                    self.category = nil
                }
            }
        }

        /// 分類篩選;`nil` 是全部分類。
        public var category: TransactionCategory?

        /// 帳戶篩選(上游 ADR 0019，送到後端查詢);`nil` 是全部帳戶。
        public var account: AccountChoice?

        init(from: CalendarDay, to: CalendarDay) {
            self.from = from
            self.to = to
        }

        /// 分類選項隨類型改變;全部類型時是支出加收入，「其他」只出現一次。
        public var categoryOptions: [TransactionCategory] {
            switch type {
            case .expense:
                TransactionCategory.expenseCategories
            case .income:
                TransactionCategory.incomeCategories
            case .all:
                TransactionCategory.expenseCategories
                    + TransactionCategory.incomeCategories.filter { !TransactionCategory.expenseCategories.contains($0) }
            }
        }

    }
}

/// 篩選裡可選的帳戶:ID 送到後端，名稱給畫面與 VoiceOver 用。
public struct AccountChoice: Hashable, Sendable {
    public let id: AccountID
    public let name: String

    public init(id: AccountID, name: String) {
        self.id = id
        self.name = name
    }
}

extension AccountScope {
    /// 記帳頁的視角對應的帳戶檢視範圍(名稱相同、語意相同)。
    init(_ scope: ViewScope) {
        switch scope {
        case .all: self = .all
        case .household: self = .household
        case .personal: self = .personal
        }
    }
}
