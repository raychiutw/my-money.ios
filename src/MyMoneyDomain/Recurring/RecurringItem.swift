import Foundation

/// 固定收支項目的 ID,由後端產生。
public struct RecurringItemID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 固定收支的週期。raw value 是後端的 `cycle`。
public enum RecurringCycle: String, CaseIterable, Hashable, Sendable {
    case monthly
    case bimonthly
    case quarterly
    case semiannual
    case annual

    /// 一期有幾個月。
    public var months: Int {
        switch self {
        case .monthly: 1
        case .bimonthly: 2
        case .quarterly: 3
        case .semiannual: 6
        case .annual: 12
        }
    }
}

/// 固定收支(RecurringItem):只是提醒與估算，**不會**自動產生交易紀錄。只有自己的項目。
public struct RecurringItem: Hashable, Sendable, Identifiable {
    public let id: RecurringItemID
    public let name: String
    public let type: TransactionType
    /// 每期金額。
    public let amount: Money
    public let cycle: RecurringCycle
    /// 扣款日或入帳日(1 到 31)。
    public let dayOfCycle: Int
    /// 關聯帳戶;沒有指定時是 `nil`。
    public let accountID: AccountID?
    public let accountName: String?

    public init(
        id: RecurringItemID,
        name: String,
        type: TransactionType,
        amount: Money,
        cycle: RecurringCycle,
        dayOfCycle: Int,
        accountID: AccountID?,
        accountName: String?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.cycle = cycle
        self.dayOfCycle = dayOfCycle
        self.accountID = accountID
        self.accountName = accountName
    }

    /// 週期攤提：每期金額平均到每個月(跟 web 一樣是 `amount / 月數`)。
    public var monthlyAmortization: Money {
        Money(amount.amount / Decimal(cycle.months))
    }
}

/// 新增或編輯固定收支時送出的內容。
public struct RecurringDraft: Hashable, Sendable {
    public let name: String
    public let type: TransactionType
    public let amount: Money
    public let cycle: RecurringCycle
    public let dayOfCycle: Int
    public let accountID: AccountID?

    public init(name: String, type: TransactionType, amount: Money, cycle: RecurringCycle, dayOfCycle: Int, accountID: AccountID?) {
        self.name = name
        self.type = type
        self.amount = amount
        self.cycle = cycle
        self.dayOfCycle = dayOfCycle
        self.accountID = accountID
    }
}

/// 固定支出與固定收入各自的週期攤提合計(後端算好的 `GET /recurring/amortize`)。
public struct RecurringAmortization: Hashable, Sendable {
    public let monthlyExpense: Money
    public let monthlyIncome: Money

    public init(monthlyExpense: Money, monthlyIncome: Money) {
        self.monthlyExpense = monthlyExpense
        self.monthlyIncome = monthlyIncome
    }

    public static let zero = RecurringAmortization(monthlyExpense: .zero, monthlyIncome: .zero)
}

/// 固定收支(`/recurring`)。
public protocol RecurringRepository: Sendable {
    /// 自己的固定收支，帶上關聯帳戶的名稱。
    func items() async throws -> [RecurringItem]

    func amortization() async throws -> RecurringAmortization

    func create(_ draft: RecurringDraft) async throws

    func update(_ id: RecurringItemID, with draft: RecurringDraft) async throws

    func delete(_ id: RecurringItemID) async throws

    /// 自己的固定收支的 CSV(`GET /export/recurring`,UTF-8 加 BOM),原樣回傳。
    func exportCSV() async throws -> Data
}
