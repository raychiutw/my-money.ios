/// 一個支出分類在當月的合計(不含「信用卡還款」,後端算好)。
public struct CategoryExpense: Hashable, Sendable {
    public let category: TransactionCategory
    public let total: Money

    public init(category: TransactionCategory, total: Money) {
        self.category = category
        self.total = total
    }
}

/// 收支趨勢的一個月：收入與支出合計(不含「信用卡還款」,後端算好)。
public struct MonthlySummary: Hashable, Sendable {
    public let month: CalendarMonth
    public let income: Money
    public let expense: Money

    public init(month: CalendarMonth, income: Money, expense: Money) {
        self.month = month
        self.income = income
        self.expense = expense
    }
}

/// 一位家庭成員當月的公帳代墊款：他記的家庭公帳支出合計。
public struct HouseholdShare: Hashable, Sendable {
    public let userID: UserID
    public let userName: String
    public let total: Money

    public init(userID: UserID, userName: String, total: Money) {
        self.userID = userID
        self.userName = userName
        self.total = total
    }
}

/// 預算額度(Budget):屬於個人，每個月各自一份，設定後無法刪除。
public struct Budget: Hashable, Sendable {
    public let category: TransactionCategory
    public let amount: Money
    /// 已花：當月該分類中我記的支出合計，不隨視角改變(後端算好)。
    public let spent: Money
    /// 超支：已花超過預算額度(後端算好)。
    public let isOver: Bool

    public init(category: TransactionCategory, amount: Money, spent: Money, isOver: Bool) {
        self.category = category
        self.amount = amount
        self.spent = spent
        self.isOver = isOver
    }
}

/// 統計(`/transactions/summary/*`)與預算額度(`/budgets`)。
public protocol StatisticsRepository: Sendable {
    /// 當月各支出分類的合計，依金額由大到小。
    func categoryExpenses(month: CalendarMonth, scope: ViewScope) async throws -> [CategoryExpense]

    /// 一整年每個月的收入與支出，依月份排序;沒有紀錄的月份不會出現。
    func monthlySummaries(year: Int, scope: ViewScope) async throws -> [MonthlySummary]

    /// 當月每位家庭成員的公帳代墊款，由多到少;沒有家庭群組時是空的。不隨視角改變。
    func householdShares(month: CalendarMonth) async throws -> [HouseholdShare]

    /// 當月設定過的預算額度。
    func budgets(month: CalendarMonth) async throws -> [Budget]

    /// 設定(新增或調整)預算額度。
    func setBudget(_ amount: Money, for category: TransactionCategory, month: CalendarMonth) async throws
}
