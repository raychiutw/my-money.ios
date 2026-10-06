/// 儲蓄目標的 ID,由後端產生。
public struct SavingsGoalID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 儲蓄目標(Savings Goal):只有自己的目標。存入**不會**動到任何資產帳戶。
public struct SavingsGoal: Hashable, Sendable, Identifiable {
    public let id: SavingsGoalID
    public let name: String
    public let icon: SavingsGoalIcon
    public let targetAmount: Money
    /// 已存金額;後端把它的上限卡在目標金額。
    public let savedAmount: Money
    /// 每月預留額;沒有設定時是 0。
    public let monthlyReserve: Money
    public let deadline: CalendarDay?

    public init(
        id: SavingsGoalID,
        name: String,
        icon: SavingsGoalIcon,
        targetAmount: Money,
        savedAmount: Money,
        monthlyReserve: Money,
        deadline: CalendarDay?
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.monthlyReserve = monthlyReserve
        self.deadline = deadline
    }

    /// 已存金額達到目標金額。
    public var isAchieved: Bool {
        savedAmount >= targetAmount
    }
}

/// 建立或編輯儲蓄目標時送出的內容。
public struct SavingsGoalDraft: Hashable, Sendable {
    public let name: String
    public let icon: SavingsGoalIcon
    public let targetAmount: Money
    public let monthlyReserve: Money
    /// `nil` 是沒有截止日;編輯時等於移除截止日。
    public let deadline: CalendarDay?

    public init(name: String, icon: SavingsGoalIcon, targetAmount: Money, monthlyReserve: Money, deadline: CalendarDay?) {
        self.name = name
        self.icon = icon
        self.targetAmount = targetAmount
        self.monthlyReserve = monthlyReserve
        self.deadline = deadline
    }
}

/// 儲蓄目標(`/goals`)。
public protocol SavingsGoalRepository: Sendable {
    /// 自己的儲蓄目標，依建立順序。
    func goals() async throws -> [SavingsGoal]

    func create(_ draft: SavingsGoalDraft) async throws

    func update(_ id: SavingsGoalID, with draft: SavingsGoalDraft) async throws

    /// 存入;後端把已存金額的上限卡在目標金額。
    func deposit(_ amount: Money, into id: SavingsGoalID) async throws

    func delete(_ id: SavingsGoalID) async throws
}
