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

    /// 關鍵字：不分大小寫，比對備註、分類、帳戶名稱與記帳人。
    public var keyword = ""

    public private(set) var phase: Phase = .loading

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    public let deleteConfirmation = "確定要刪除這筆交易記錄嗎？"

    /// 從後端載入的區間內所有交易記錄(篩選前)。
    private var loaded: [Transaction] = []

    @ObservationIgnored private let repository: any TransactionRepository
    @ObservationIgnored private let accountRepository: (any AccountRepository)?
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let currentUser: UserID?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var loadedVersion: Int?

    /// `currentUser` 是登入的人：自己記的交易記錄不顯示記帳人。`locale` 決定日期的格式，預設跟著系統。
    public init(
        repository: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        dataVersion: DataVersion,
        currentUser: UserID? = nil,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.currentUser = currentUser
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

    /// 按「完成」:套用草稿。視角或起迄日改了才重新查詢，而且只查詢一次;類型、分類只在本機過濾。
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

    /// 導覽列副標題：目前套用的範圍，例如「家庭公帳・9月1日–9月30日・支出・餐飲」;預設時是「全部・9月1日–9月29日」。
    /// 日期用系統格式(DESIGN.md「日期」)。
    public var subtitle: String {
        let today = today()
        var parts = [
            filter.scope.title,
            "\(filter.from.text(today: today, locale: locale))–\(filter.to.text(today: today, locale: locale))",
        ]
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

    private var filtered: [Transaction] {
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
            let transactions = try await repository.allTransactions(from: query.from, to: query.to, scope: query.scope)
            // 套用篩選和第一次載入各自是一個 Task,舊的查詢可能比較晚回來：篩選已經改了就丟掉。
            guard query == filter.query else { return }
            loaded = transactions
            loadedVersion = version
            phase = .loaded
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

    /// 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷)是系統內部平帳或轉帳的紀錄，不能編輯也不能刪除(後端也會拒絕)。
    public func canModify(_ transaction: Transaction) -> Bool {
        !transaction.isSystemRecord
    }

    /// 交易記錄列的記帳人：只有不是自己記的才顯示(#72)。
    public func recorderName(of transaction: Transaction) -> String? {
        transaction.recorderName(besides: currentUser)
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
    private static func income(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .income && !$0.isSystemRecord }.reduce(.zero) { $0 + $1.amount }
    }

    /// 支出合計，不含系統分類：信用卡扣款還款、轉帳、ATM 提款、報銷只是資金調度，算進來會跟刷卡或原本的消費重複。
    private static func expense(of transactions: [Transaction]) -> Money {
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
            Query(scope: scope, from: from, to: to)
        }

        struct Query: Equatable {
            let scope: ViewScope
            let from: CalendarDay
            let to: CalendarDay
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
