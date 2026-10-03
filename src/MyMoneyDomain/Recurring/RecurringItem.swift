import Foundation

/// 週期收支項目的 ID,由後端產生。
public struct RecurringItemID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 週期收支的週期。raw value 是後端的 `cycle`。
public enum RecurringCycle: String, CaseIterable, Hashable, Sendable {
    case monthly
    case bimonthly
    case quarterly
    case semiannual
    case annual

    /// 可選的繳費月份(`month_of_cycle`，上游 ADR 0012):從哪一個月開始算，之後每隔一期扣款一次。
    /// 月繳固定 1;雙月繳 1–2(單數月、雙數月);季繳 1–3;半年繳 1–6;年繳 1–12。
    public var monthChoices: [Int] { Array(1...months) }

    /// 切換週期時的月份:不在新週期範圍內就重設為第一項(1)，範圍內的保留(跟 web 的 `handleCycleChange` 一樣)。
    public func clampedMonth(_ month: Int) -> Int {
        monthChoices.contains(month) ? month : monthChoices[0]
    }

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

/// 週期收支(RecurringItem):只是提醒與估算，**不會**自動產生交易記錄。
/// 上游 ADR 0016 起有歸屬(家庭公帳或個人私帳)，視角是「全部」或「家庭公帳」時也包含家人建立的家庭公帳項目。
public struct RecurringItem: Hashable, Sendable, Identifiable {
    public let id: RecurringItemID
    public let name: String
    public let type: TransactionType
    /// 每期金額。
    public let amount: Money
    public let cycle: RecurringCycle
    /// 扣款日或入帳日(1 到 31)。
    public let dayOfCycle: Int
    /// 繳費月份(`month_of_cycle`):月繳是 1;舊資料沒有這個欄位時也是 1(見 `RecurringCycle.monthChoices`)。
    public let monthOfCycle: Int
    /// 關聯帳戶;沒有指定時是 `nil`。
    public let accountID: AccountID?
    public let accountName: String?
    /// 歸屬(後端 `is_shared`):家庭公帳是 `true`，個人私帳是 `false`;舊資料沒有這個欄位時是個人私帳。
    public let isShared: Bool
    /// 建立者(後端 `user_id`、`user_name`):判斷能不能改、畫面寫「建立者・歸屬」。不知道時是 `nil`。
    public let ownerID: UserID?
    public let ownerName: String?

    public init(
        id: RecurringItemID,
        name: String,
        type: TransactionType,
        amount: Money,
        cycle: RecurringCycle,
        dayOfCycle: Int,
        monthOfCycle: Int = 1,
        accountID: AccountID?,
        accountName: String?,
        isShared: Bool = false,
        ownerID: UserID? = nil,
        ownerName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.cycle = cycle
        self.dayOfCycle = dayOfCycle
        self.monthOfCycle = monthOfCycle
        self.accountID = accountID
        self.accountName = accountName
        self.isShared = isShared
        self.ownerID = ownerID
        self.ownerName = ownerName
    }

    /// 分攤平滑：每期金額平均到每個月(跟 web 一樣是 `amount / 月數`)。
    public var monthlyAmortization: Money {
        Money(amount.amount / Decimal(cycle.months))
    }
}

/// 新增或編輯週期收支時送出的內容。
public struct RecurringDraft: Hashable, Sendable {
    public let name: String
    public let type: TransactionType
    public let amount: Money
    public let cycle: RecurringCycle
    public let dayOfCycle: Int
    public let monthOfCycle: Int
    public let accountID: AccountID?
    /// 歸屬(後端 `is_shared`，上游 ADR 0016):家庭公帳是 `true`。
    public let isShared: Bool

    public init(
        name: String, type: TransactionType, amount: Money, cycle: RecurringCycle, dayOfCycle: Int, monthOfCycle: Int = 1,
        accountID: AccountID?, isShared: Bool = false
    ) {
        self.name = name
        self.type = type
        self.amount = amount
        self.cycle = cycle
        self.dayOfCycle = dayOfCycle
        self.monthOfCycle = monthOfCycle
        self.accountID = accountID
        self.isShared = isShared
    }
}

/// 週期支出與週期收入各自的分攤平滑合計(後端算好的 `GET /recurring/amortize`)。
public struct RecurringAmortization: Hashable, Sendable {
    public let monthlyExpense: Money
    public let monthlyIncome: Money

    public init(monthlyExpense: Money, monthlyIncome: Money) {
        self.monthlyExpense = monthlyExpense
        self.monthlyIncome = monthlyIncome
    }

    public static let zero = RecurringAmortization(monthlyExpense: .zero, monthlyIncome: .zero)
}

/// 週期收支(`/recurring`)。
public protocol RecurringRepository: Sendable {
    /// 這個視角的週期收支，帶上關聯帳戶的名稱與建立者:全部是我建立的加上家人的家庭公帳;
    /// 家庭公帳是全家人的家庭公帳項目;個人私帳是我建立的個人私帳項目(上游 ADR 0016)。
    func items(scope: ViewScope) async throws -> [RecurringItem]

    /// 這個視角的分攤平滑合計。
    func amortization(scope: ViewScope) async throws -> RecurringAmortization

    func create(_ draft: RecurringDraft) async throws

    func update(_ id: RecurringItemID, with draft: RecurringDraft) async throws

    func delete(_ id: RecurringItemID) async throws

    /// 自己的週期收支的 CSV(`GET /export/recurring`,UTF-8 加 BOM),原樣回傳。
    func exportCSV() async throws -> Data
}
