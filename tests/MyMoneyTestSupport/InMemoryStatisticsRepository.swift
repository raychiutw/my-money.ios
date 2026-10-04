import Foundation
import MyMoneyDomain

/// 不連網路的統計與預算額度：資料由測試決定，並記下每一次查詢。
///
/// 分類支出依視角各給一份;視角的篩選是後端的規則，這裡不模擬(ADR-0001)。
public actor InMemoryStatisticsRepository: StatisticsRepository {
    public struct CategoryQuery: Hashable, Sendable {
        public let month: CalendarMonth
        public let scope: ViewScope

        public init(month: CalendarMonth, scope: ViewScope) {
            self.month = month
            self.scope = scope
        }
    }

    public struct MonthlyQuery: Hashable, Sendable {
        public let year: Int
        public let scope: ViewScope

        public init(year: Int, scope: ViewScope) {
            self.year = year
            self.scope = scope
        }
    }

    public struct SetBudget: Hashable, Sendable {
        public let category: TransactionCategory
        public let amount: Money
        public let month: CalendarMonth

        public init(category: TransactionCategory, amount: Money, month: CalendarMonth) {
            self.category = category
            self.amount = amount
            self.month = month
        }
    }

    private let expensesByScope: [ViewScope: [CategoryExpense]]
    private let summaries: [MonthlySummary]
    private let shares: [HouseholdShare]
    private var storedBudgets: [Budget]
    private var failure: RepositoryError?
    /// 只讓家庭的公帳代墊統計失敗(總覽的「家庭」入口獨立失敗，#178);其他查詢照常。
    private var sharesFailure: RepositoryError?
    /// 有設定時，收支趨勢改從這些收支明細算(UI 測試記一筆之後，總覽的當月淨收支才會變)。
    private let transactions: InMemoryTransactionRepository?

    public private(set) var categoryQueries: [CategoryQuery] = []
    public private(set) var monthlyQueries: [MonthlyQuery] = []
    public private(set) var shareQueries: [CalendarMonth] = []
    public private(set) var budgetQueries: [CalendarMonth] = []
    public private(set) var setBudgets: [SetBudget] = []

    public init(
        expensesByScope: [ViewScope: [CategoryExpense]],
        summaries: [MonthlySummary],
        shares: [HouseholdShare],
        budgets: [Budget],
        transactions: InMemoryTransactionRepository? = nil
    ) {
        self.expensesByScope = expensesByScope
        self.summaries = summaries
        self.shares = shares
        storedBudgets = budgets
        self.transactions = transactions
    }

    /// 以台灣時間的本月產生(給 `-uiTesting` 的 composition root 用);收支趨勢從 `transactions` 算。
    public static func sampleForToday(transactions: InMemoryTransactionRepository) -> InMemoryStatisticsRepository {
        sample(month: CalendarMonth(CalendarDay.today()), transactions: transactions)
    }

    /// 截圖巡覽用(`-uiTestingManyCategories`):15 種支出分類有支出，圓餅圖才看得到「最多 8 塊、其餘併成灰色」(#100)。
    /// 留一種(寵物毛孩)沒有支出，「新增預算額度」才還有分類可以新增(全部都列出時按鈕不顯示)。
    /// 金額由大到小，交錯有專屬色與沒有專屬色的分類;其他跟 `sample` 一樣。
    public static func sampleWithEveryCategoryForToday(transactions: InMemoryTransactionRepository) -> InMemoryStatisticsRepository {
        sampleWithEveryCategory(month: CalendarMonth(CalendarDay.today()), transactions: transactions)
    }

    static func sampleWithEveryCategory(
        month: CalendarMonth, transactions: InMemoryTransactionRepository? = nil
    ) -> InMemoryStatisticsRepository {
        let order = [
            "購物", "保險稅費", "餐飲", "居家水電", "交通", "數位訂閱", "汽機車輛", "生活",
            "社交人情", "娛樂", "旅行度假", "醫療", "美妝保養", "教育", "其他",
        ]
        let spending = order.enumerated().map { index, name in
            CategoryExpense(category: TransactionCategory(name), total: Money(Decimal(9000 - index * 500)))
        }
        return sample(month: month, transactions: transactions, spending: spending)
    }

    /// 我記的:購物 880、交通 250、餐飲 120;家庭視角只有餐飲 120。
    /// 預算額度：餐飲 100(超支)、購物 1000(接近上限)。公帳代墊款：小明 6000、小美 4000。
    public static func sample(
        month: CalendarMonth, shares: [HouseholdShare]? = nil, transactions: InMemoryTransactionRepository? = nil,
        spending: [CategoryExpense]? = nil
    ) -> InMemoryStatisticsRepository {
        let mine = spending ?? [
            CategoryExpense(category: TransactionCategory("購物"), total: Money(880)),
            CategoryExpense(category: TransactionCategory("交通"), total: Money(250)),
            CategoryExpense(category: .dining, total: Money(120)),
        ]
        return InMemoryStatisticsRepository(
            expensesByScope: [.all: mine, .personal: mine, .household: [CategoryExpense(category: .dining, total: Money(120))]],
            summaries: [MonthlySummary(month: month, income: Money(45000), expense: Money(1250))],
            shares: shares ?? [
                HouseholdShare(userID: UserID("sample-ming"), userName: "小明", total: Money(6000)),
                HouseholdShare(userID: UserID("sample-mei"), userName: "小美", total: Money(4000)),
            ],
            budgets: [
                Budget(category: .dining, amount: Money(100), spent: Money(120), isOver: true),
                Budget(category: TransactionCategory("購物"), amount: Money(1000), spent: Money(880), isOver: false),
            ],
            transactions: transactions
        )
    }

    public func categoryExpenses(month: CalendarMonth, scope: ViewScope) async throws -> [CategoryExpense] {
        categoryQueries.append(CategoryQuery(month: month, scope: scope))
        if let failure { throw failure }
        return expensesByScope[scope] ?? []
    }

    public func monthlySummaries(year: Int, scope: ViewScope) async throws -> [MonthlySummary] {
        monthlyQueries.append(MonthlyQuery(year: year, scope: scope))
        if let failure { throw failure }
        if let transactions { return await transactions.monthlySummaries(year: year) }
        return summaries.filter { $0.month.year == year }
    }

    public func householdShares(month: CalendarMonth) async throws -> [HouseholdShare] {
        shareQueries.append(month)
        if let failure { throw failure }
        if let sharesFailure { throw sharesFailure }
        return shares
    }

    public func budgets(month: CalendarMonth) async throws -> [Budget] {
        budgetQueries.append(month)
        if let failure { throw failure }
        return storedBudgets
    }

    /// 跟後端一樣新增或調整;已花用個人視角的分類支出(測試用的替身)。
    public func setBudget(_ amount: Money, for category: TransactionCategory, month: CalendarMonth) async throws {
        if let failure { throw failure }
        setBudgets.append(SetBudget(category: category, amount: amount, month: month))
        let spent = expensesByScope[.personal]?.first { $0.category == category }?.total ?? .zero
        let budget = Budget(category: category, amount: amount, spent: spent, isOver: amount < spent)
        storedBudgets.removeAll { $0.category == category }
        storedBudgets.append(budget)
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 之後只有公帳代墊統計(`householdShares`)以這個錯誤失敗。
    public func failHouseholdShares(with error: RepositoryError) {
        sharesFailure = error
    }
}
