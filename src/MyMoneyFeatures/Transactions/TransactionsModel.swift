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

    /// 當日淨額(收入減支出，不含系統分類，#118)。
    public var net: Money { income - expense }

    /// 當天有收入或支出才有淨額可以顯示;只有信用卡還款這類系統分類的那天沒有。
    public var hasNet: Bool { income > .zero || expense > .zero }

    /// 日標頭右邊的淨額，帶正負號，例如「+$45,000」「−$1,000」;零是「$0」。
    public var netText: String { net.signedFormatted() }
}

/// 交易頁的 model(parity.md「交易」)。
///
/// 起迄日與視角送到後端查詢;類型、分類、關鍵字只在本機過濾(跟 web 一樣)。
/// 視角、起迄日、類型、分類在篩選 sheet 裡改一份草稿，按「完成」才套用(#74);關鍵字照舊即時過濾。
@MainActor
@Observable
public final class TransactionsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 類型篩選(只在本機過濾)。
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

    /// 從後端載入的區間內所有交易記錄(篩選前)。
    private var loaded: [Transaction] = []

    @ObservationIgnored private let repository: any TransactionRepository
    @ObservationIgnored private let accountRepository: (any AccountRepository)?
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let currentUser: UserID?
    /// 編輯與刪除的權限(上游 ADR 0013、#133);沒有就不擋，交給後端。
    @ObservationIgnored private let permissions: PermissionsModel?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadedVersion: Int?

    /// 骨架屏每天的列數(#204 核對):上次載入完成時前三天各有幾筆(每天最多 4);第一次沒有記錄時兩天、3 與 2 筆。
    public var skeletonDayRows: [Int] {
        let stored = defaults.array(forKey: "skeleton.transactions.dayRows") as? [Int]
        return (stored?.isEmpty == false ? stored : nil) ?? [3, 2]
    }

    /// `currentUser` 是登入的人：自己記的交易記錄不顯示記帳人。`locale` 決定日期的格式，預設跟著系統。
    public init(
        repository: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        dataVersion: DataVersion,
        currentUser: UserID? = nil,
        permissions: PermissionsModel? = nil,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.defaults = defaults
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.currentUser = currentUser
        self.permissions = permissions
        self.locale = locale
        self.today = today
        let now = today()
        let thisMonth = Filter(from: now.firstOfMonth, to: now)
        filter = thisMonth
        filterDraft = thisMonth
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

    /// 按「完成」:套用草稿。視角、起迄日或帳戶改了才重新查詢，而且只查詢一次;類型、分類只在本機過濾。
    public func applyFilter() async {
        isEditingFilter = false
        let needsQuery = filterDraft.query != filter.query
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
        for transaction in filtered {
            if byDay[transaction.date] == nil { order.append(transaction.date) }
            byDay[transaction.date, default: []].append(transaction)
        }
        let today = today()
        return order.sorted(by: >).map { date in
            let items = byDay[date] ?? []
            return TransactionDay(
                date: date, title: date.headerText(today: today, locale: locale), transactions: items,
                income: Self.income(of: items), expense: Self.expense(of: items)
            )
        }
    }

    public var count: Int { filtered.count }
    public var totalIncome: Money { Self.income(of: filtered) }
    /// 總支出不含「信用卡還款」(parity 刻意偏離第 26 項)。
    public var totalExpense: Money { Self.expense(of: filtered) }
    public var net: Money { totalIncome - totalExpense }

    /// 今天(台灣時間)與地區:`TransactionsModel+Numbers` 的日期文字用。
    var todayValue: CalendarDay { today() }
    var localeValue: Locale { locale }

    /// 套用類型、分類與關鍵字之後的交易記錄;摘要、比例條和長條圖都用它。
    var filtered: [Transaction] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return loaded.filter { transaction in
            switch filter.type {
            case .all: break
            case .expense: if transaction.type != .expense { return false }
            case .income: if transaction.type != .income { return false }
            }
            if let category = filter.category, transaction.category != category { return false }
            guard !needle.isEmpty else { return true }
            return [transaction.note, transaction.category.name, transaction.accountName ?? "", transaction.recorderName ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    /// 依目前套用的起迄日與視角，抓齊區間內的所有交易記錄。
    public func load() async {
        let version = dataVersion.value
        let query = filter.query
        do {
            let transactions = try await repository.allTransactions(
                from: query.from, to: query.to, scope: query.scope, accountID: query.accountID
            )
            // 套用篩選和第一次載入各自是一個 Task,舊的查詢可能比較晚回來：篩選已經改了就丟掉。
            guard query == filter.query else { return }
            loaded = transactions
            loadedVersion = version
            defaults.set(days.prefix(3).map { min($0.transactions.count, 4) }, forKey: "skeleton.transactions.dayRows")
            phase = .loaded
            await permissions?.loadIfNeeded()
        } catch {
            guard query == filter.query else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
        await load()
    }

    /// 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷)是系統內部平帳或轉帳的紀錄，不能編輯也不能刪除(後端也會拒絕);
    /// 再跟權限取交集(上游 ADR 0013、#133):個人私帳只有記錄者，家庭公帳是記錄者或家庭管理員。
    public func canModify(_ transaction: Transaction) -> Bool {
        !transaction.isSystemRecord && (permissions?.current.canModify(transaction) ?? true)
    }

    /// 點不開的列為什麼不能編輯(點一下跳出的說明);可以改的是 `nil`。
    public func lockReason(for transaction: Transaction) -> String? {
        if transaction.isSystemRecord { return "系統紀錄，不能編輯或刪除" }
        if canModify(transaction) { return nil }
        return transaction.isShared ? "他人記錄的\(OwnershipName.household)，僅記錄者或家庭管理員可以編輯、刪除" : "他人的\(OwnershipName.personal)，僅記錄者本人可以編輯、刪除"
    }

    /// 說明 alert 的標題(#146)。
    public let lockAlertTitle = "不能編輯這筆\(Terms.transactions)"

    /// 點不開的列的 VoiceOver 提示;原因不再塞在整句最後，點了才跳出說明(#146)。可以改的是 `nil`。
    public func lockHint(for transaction: Transaction) -> String? {
        lockReason(for: transaction) == nil ? nil : "點兩下查看為什麼不能編輯"
    }

    /// 交易記錄列的記帳人：只有不是自己記的才顯示(#72)。
    public func recorderName(of transaction: Transaction) -> String? {
        transaction.recorderName(besides: currentUser)
    }

    /// 交易列的次要文字「記帳人・歸屬」(#145):自己記的也顯示;系統自動產生的紀錄記帳人寫「系統紀錄」;
    /// 沒有記帳人名稱時只寫歸屬。
    public func subtitle(of transaction: Transaction) -> TransactionSubtitle {
        TransactionSubtitle(
            recorder: transaction.isSystemRecord ? "系統紀錄" : transaction.recorderName,
            ownership: OwnershipName.title(isShared: transaction.isShared),
            billing: transaction.billing.label,
            time: transaction.recordedAt.map(RecordedTime.clockText(of:))
        )
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
        do {
            try await repository.delete(transaction.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 目前起迄日的 CSV,檔名跟 web 一樣是 `my-money-今天.csv`。
    public func csvExport() -> CSVExport {
        let repository = repository
        let (from, to) = (filter.from, filter.to)
        return CSVExport(fileName: "my-money-\(today().iso).csv") {
            try await repository.exportCSV(from: from, to: to)
        }
    }

    /// 收入合計，不含系統分類(ATM 提款、轉帳、報銷的收入那一筆也只是資金調度)。
    static func income(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .income && !$0.isSystemRecord }.reduce(.zero) { $0 + $1.amount }
    }

    /// 支出合計，不含系統分類：信用卡扣款還款、轉帳、ATM 提款、報銷只是資金調度，算進來會跟刷卡或原本的消費重複。
    static func expense(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .expense && !$0.isSystemRecord }.reduce(.zero) { $0 + $1.amount }
    }
}

extension TransactionsModel {
    /// 交易頁的篩選，也是篩選 sheet 的草稿。視角與起迄日送到後端查詢;類型、分類只在本機過濾(跟 web 一樣)。
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

        /// 送到後端查詢的部分。
        var query: Query {
            Query(scope: scope, from: from, to: to, accountID: account?.id)
        }

        struct Query: Equatable {
            let scope: ViewScope
            let from: CalendarDay
            let to: CalendarDay
            let accountID: AccountID?
        }
    }
}

/// 交易列的次要文字:記帳人與歸屬分開存放，畫面放不下時先截記帳人的名稱、歸屬保留(#145)。
public struct TransactionSubtitle: Equatable, Sendable {
    public let recorder: String?
    public let ownership: String
    /// 信用卡的帳單狀態標籤「已出帳」「延至下期」(上游 ADR 0020，#188);其他沒有。
    public let billing: String?
    /// 記帳時間(台灣時間 HH:mm,上游 718ace9、#207);沒有時間資料是 `nil`。放在最前面。
    public let time: String?

    public init(recorder: String?, ownership: String, billing: String? = nil, time: String? = nil) {
        self.time = time
        self.recorder = recorder
        self.ownership = ownership
        self.billing = billing
    }

    /// 歸屬加帳單狀態標籤,例如「家庭公帳・延至下期」:畫面放不下時這一段保留，先截記帳人的名稱。
    public var tail: String {
        [ownership, billing].compactMap { $0 }.joined(separator: "・")
    }

    /// 例如「14:05・小美・家庭公帳・延至下期」;沒有時間就沒有最前面那一段,沒有記帳人名稱時只有歸屬(與標籤)。
    public var text: String {
        [time, recorder, tail].compactMap { $0 }.joined(separator: "・")
    }
}

extension BillingStatus {
    /// 列上的標籤;未出帳不標。
    var label: String? {
        switch self {
        case .unbilled: nil
        case .billed: Terms.billed
        case .deferred: Terms.deferredToNextStatement
        }
    }
}

extension Transaction {
    /// 記帳人的名稱;`user` 自己記的是 `nil`。用 ID 判斷，家人可能同名。
    func recorderName(besides user: UserID?) -> String? {
        guard let user, recorderID == user else { return recorderName }
        return nil
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
