import Foundation
import MyMoneyDomain
import Observation

/// 預算清單的一列：一個支出分類的已花與預算額度。
public struct BudgetRow: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        /// 沒有設定預算額度。
        case unset
        case normal
        /// 已花達到預算額度的 80% 以上，但還沒超支。
        case nearLimit
        case over(by: Money)
    }

    public let category: TransactionCategory
    public let budget: Budget?
    /// 已花：有預算額度時用後端的 `spent`,沒有時用個人視角的分類支出(兩者都是我記的支出)。
    public let spent: Money

    public init(category: TransactionCategory, budget: Budget?, fallbackSpent: Money) {
        self.category = category
        self.budget = budget
        spent = budget?.spent ?? fallbackSpent
    }

    public var id: String { category.name }

    /// 超支用後端的 `over`;接近上限是已花達到預算額度的 80%。
    public var status: Status {
        guard let budget else { return .unset }
        if budget.isOver { return .over(by: spent - budget.amount) }
        return spent.amount * 10 >= budget.amount.amount * 8 ? .nearLimit : .normal
    }
}

/// 分攤建議：剛好兩人有公帳代墊款時，平分當月家庭公帳總額後，誰該轉多少給誰。
public struct Settlement: Equatable, Sendable {
    public struct Transfer: Equatable, Sendable {
        public let from: String
        public let to: String
        public let amount: Money

        public init(from: String, to: String, amount: Money) {
            self.from = from
            self.to = to
            self.amount = amount
        }
    }

    /// 每人應負擔的金額(四捨五入到整數)。
    public let perPerson: Money
    /// 兩人的公帳代墊款一樣多時是 `nil`。
    public let transfer: Transfer?

    public init(perPerson: Money, transfer: Transfer?) {
        self.perPerson = perPerson
        self.transfer = transfer
    }
}

/// 統計 tab 的 model(parity.md「統計與預算」)。
@MainActor
@Observable
public final class StatisticsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 預設本月(台灣時間)。
    public var month: CalendarMonth
    public var scope: ViewScope = .all

    public private(set) var phase: Phase = .loading
    public private(set) var categoryExpenses: [CategoryExpense] = []
    public private(set) var monthlySummaries: [MonthlySummary] = []
    public private(set) var householdShares: [HouseholdShare] = []
    /// 預算額度清單：有預算或本月已花的支出分類，依支出分類的固定順序。
    public private(set) var budgetRows: [BudgetRow] = []

    /// 支出分類圓餅圖:最多 8 塊，金額最大的幾種各用固定色，其餘併成灰色(#100)。
    public var expenseChart: ExpenseChart { ExpenseChart(expenses: categoryExpenses) }

    /// 清單沒列出的支出分類，依固定順序;全部都列出時是空的，不顯示「新增預算額度」。
    public var addableBudgetCategories: [TransactionCategory] {
        let listed = Set(budgetRows.map(\.category))
        return BudgetEditorModel.categories.filter { !listed.contains($0) }
    }

    @ObservationIgnored private let repository: any StatisticsRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let defaults: UserDefaults

    /// 骨架屏的分類列數與預算列數(#204 核對);第一次沒有記錄時各 3。
    public struct SkeletonCounts: Equatable, Sendable {
        public let categories: Int
        public let budgets: Int

        public init(categories: Int, budgets: Int) {
            self.categories = categories
            self.budgets = budgets
        }
    }

    private var skeletonMemory: SkeletonShapeMemory { SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.statistics") }

    public var skeletonCounts: SkeletonCounts {
        SkeletonCounts(
            categories: skeletonMemory.count(for: "categories", default: 3, limit: 6),
            budgets: skeletonMemory.count(for: "budgets", default: 3, limit: 6)
        )
    }

    /// `locale` 決定月份的格式，預設跟著系統。
    public init(
        repository: any StatisticsRepository,
        dataVersion: DataVersion,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.defaults = defaults
        self.repository = repository
        self.dataVersion = dataVersion
        self.locale = locale
        currentMonth = CalendarMonth(today())
        month = currentMonth
    }

    /// 建立時的本月(台灣時間);切換月份不變。月份選擇器的上限用它。
    public let currentMonth: CalendarMonth

    /// 所選的月份，例如「2026年9月」(DESIGN.md「日期」)。
    public var monthTitle: String { month.text(locale: locale) }

    /// 所選月份的年份(收支趨勢),例如「2026年」。
    public var yearTitle: String { month.yearText(locale: locale) }

    /// 主數字的標題，例如「9月支出」(#120);月份在下面的月份列也有，完整的年月是 `monthTitle`。
    public var expenseTitle: String { "\(month.month)月支出" }

    public var totalCategoryExpense: Money { categoryExpenses.reduce(.zero) { $0 + $1.total } }

    /// 視角是家庭或全部、而且有公帳代墊款時才顯示。
    public var showsHouseholdShares: Bool { scope != .personal && !householdShares.isEmpty }

    /// 當月家庭公帳總額。
    public var householdTotal: Money { householdShares.reduce(.zero) { $0 + $1.total } }

    /// 一位家庭成員佔當月家庭公帳總額的比例，取 1 位小數。
    public func ratioText(_ share: HouseholdShare) -> String {
        guard householdTotal > .zero else { return "0%" }
        let ratio = share.total.amount / householdTotal.amount * 100
        return ratio.percentText(fractionDigits: 1)
    }

    public var settlement: Settlement? { Self.settlement(for: householdShares) }

    /// 跟 web 一樣：墊付少的人，轉兩人差額的一半給墊付多的人。
    public nonisolated static func settlement(for shares: [HouseholdShare]) -> Settlement? {
        guard shares.count == 2 else { return nil }
        let sorted = shares.sorted { $0.total > $1.total }
        let (more, less) = (sorted[0], sorted[1])
        let perPerson = Money(rounded((more.total + less.total).amount / 2))
        guard more.total != less.total else { return Settlement(perPerson: perPerson, transfer: nil) }
        let amount = Money(rounded((more.total - less.total).amount / 2))
        return Settlement(perPerson: perPerson, transfer: .init(from: less.userName, to: more.userName, amount: amount))
    }

    /// 四捨五入到整數，跟 web 的 `Math.round` 一樣(金額都是正數)。
    private nonisolated static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }

    /// 依目前的月份與視角載入。已花不隨視角改變，所以另外抓個人視角的分類支出。
    /// 收支趨勢帶入所選月份的年份(parity 刻意偏離第 12 項)。
    public func load() async {
        let version = dataVersion.value
        let (month, scope) = (month, scope)
        do {
            async let expenses = repository.categoryExpenses(month: month, scope: scope)
            async let mine = repository.categoryExpenses(month: month, scope: .personal)
            async let summaries = repository.monthlySummaries(year: month.year, scope: scope)
            async let shares = repository.householdShares(month: month)
            async let budgets = repository.budgets(month: month)
            let (loadedExpenses, loadedMine, loadedSummaries, loadedShares, loadedBudgets) =
                try await (expenses, mine, summaries, shares, budgets)
            // 被取消(換了月份或視角)或已經過期的結果不套用，免得舊月份的資料蓋掉新的。
            guard !Task.isCancelled, month == self.month, scope == self.scope else { return }
            categoryExpenses = loadedExpenses
            monthlySummaries = loadedSummaries
            householdShares = loadedShares
            // 只列有預算或本月已花的分類(parity 刻意偏離第 50 項)。
            budgetRows = BudgetEditorModel.categories.map { category in
                BudgetRow(
                    category: category,
                    budget: loadedBudgets.first { $0.category == category },
                    fallbackSpent: loadedMine.first { $0.category == category }?.total ?? .zero
                )
            }
            .filter { $0.budget != nil || $0.spent > .zero }
            loadedVersion = version
            skeletonMemory.record(count: categoryExpenses.count, for: "categories")
            skeletonMemory.record(count: budgetRows.count, for: "budgets")
            phase = .loaded
        } catch {
            // 被取消的載入不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, month == self.month, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
        await load()
    }

    /// 「新增預算額度」直接打開的編輯:預設選第一個還沒列出的支出分類，其他分類由編輯裡的分類格選(ADR-0004、#101)。
    /// 每個支出分類都已經列出時是 `nil`(畫面不顯示「新增預算額度」)。
    public func makeNewBudgetEditor() -> BudgetEditorModel? {
        addableBudgetCategories.first.map(makeBudgetEditor(for:))
    }

    /// 設定預算額度的 sheet:點整列和「新增預算額度」都用它，已有預算時帶入原值。
    public func makeBudgetEditor(for category: TransactionCategory) -> BudgetEditorModel {
        BudgetEditorModel(
            category: category, existing: budgetRows.first { $0.category == category }?.budget, month: month,
            monthTitle: monthTitle, repository: repository, dataVersion: dataVersion
        )
    }
}

/// 設定預算額度的 sheet。
@MainActor
@Observable
public final class BudgetEditorModel {
    /// 可以設定預算的是全部支出分類(16 種)。
    public static let categories = TransactionCategory.expenseCategories

    public var category: TransactionCategory
    public var amountText: String
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public let month: CalendarMonth
    /// 月份，例如「2026年9月」(DESIGN.md「日期」)。
    public let monthTitle: String

    @ObservationIgnored private let repository: any StatisticsRepository
    @ObservationIgnored private let dataVersion: DataVersion

    /// 已有預算額度時帶入原值，沒有時預設 5000(跟 web 一樣)。
    init(
        category: TransactionCategory,
        existing: Budget?,
        month: CalendarMonth,
        monthTitle: String,
        repository: any StatisticsRepository,
        dataVersion: DataVersion
    ) {
        self.category = category
        amountText = existing.map { "\($0.amount.amount)" } ?? "5000"
        self.month = month
        self.monthTitle = monthTitle
        self.repository = repository
        self.dataVersion = dataVersion
    }

    public var title: String { "設定 \(category.name) 的預算" }

    /// 儲存;成功時回傳 `true`(sheet 關閉)並遞增資料版本。接受任何正整數(parity 刻意偏離第 4 項)。
    public func save() async -> Bool {
        errorMessage = nil
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請輸入有效預算金額"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setBudget(amount, for: category, month: month)
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "預算設定失敗" : message
            return false
        }
        dataVersion.bump()
        return true
    }
}

extension Settlement {
    /// 分攤建議的一句話，統計頁與家庭頁共用:「平分後每人應負擔 5,000 元,小美 轉 1,000 元 給 小明」;
    /// 兩人一樣多時「…,兩人的公帳代墊款一樣多，不用轉帳」。`spoken` 時金額念成「1,000 元」。
    func text(spoken: Bool) -> String {
        let amount: (Money) -> String = { spoken ? $0.spokenText : $0.formatted() }
        let perPerson = "平分後每人應負擔 \(amount(perPerson))"
        guard let transfer else { return "\(perPerson),兩人的公帳代墊款一樣多，不用轉帳" }
        return "\(perPerson),\(transfer.from) 轉 \(amount(transfer.amount)) 給 \(transfer.to)"
    }
}
