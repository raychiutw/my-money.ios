import MyMoneyDomain

/// 不連網路的儲蓄目標，記下建立、編輯、存入、刪除的內容。
public actor InMemorySavingsGoalRepository: SavingsGoalRepository {
    public struct Deposit: Equatable, Sendable {
        public let id: SavingsGoalID
        public let amount: Money

        public init(id: SavingsGoalID, amount: Money) {
            self.id = id
            self.amount = amount
        }
    }

    private var stored: [SavingsGoal]
    private var failure: RepositoryError?

    public private(set) var createdDrafts: [SavingsGoalDraft] = []
    public private(set) var updatedDrafts: [SavingsGoalID: SavingsGoalDraft] = [:]
    public private(set) var deposits: [Deposit] = []
    public private(set) var deletedIDs: [SavingsGoalID] = []

    /// `goals()` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    /// 沖繩旅遊(有截止日)、緊急備用金(沒有截止日)、iOS 小目標(已達成)。
    public static let sampleGoals = [
        SavingsGoal(
            id: SavingsGoalID("sample-trip"), name: "沖繩旅遊", emoji: "✈️", targetAmount: Money(60000),
            savedAmount: Money(3000), monthlyReserve: Money(5000), deadline: CalendarDay(year: 2027, month: 3, day: 31)
        ),
        SavingsGoal(
            id: SavingsGoalID("sample-emergency"), name: "緊急備用金", emoji: "🏥", targetAmount: Money(100_000),
            savedAmount: .zero, monthlyReserve: .zero, deadline: nil
        ),
        SavingsGoal(
            id: SavingsGoalID("sample-achieved"), name: "iOS 小目標", emoji: "🎒", targetAmount: Money(1000),
            savedAmount: Money(1000), monthlyReserve: Money(200), deadline: CalendarDay(year: 2026, month: 12, day: 31)
        ),
    ]

    public init(goals: [SavingsGoal]) {
        stored = goals
    }

    public static func sample() -> InMemorySavingsGoalRepository {
        InMemorySavingsGoalRepository(goals: sampleGoals)
    }

    public func goals() async throws -> [SavingsGoal] {
        fetchCount += 1
        if let failure { throw failure }
        return stored
    }

    public func create(_ draft: SavingsGoalDraft) async throws {
        if let failure { throw failure }
        createdDrafts.append(draft)
        stored.append(Self.goal(SavingsGoalID("in-memory-goal-\(createdDrafts.count)"), from: draft, saved: .zero))
    }

    public func update(_ id: SavingsGoalID, with draft: SavingsGoalDraft) async throws {
        if let failure { throw failure }
        updatedDrafts[id] = draft
        stored = stored.map { $0.id == id ? Self.goal(id, from: draft, saved: $0.savedAmount) : $0 }
    }

    /// 跟後端一樣把已存金額的上限卡在目標金額(測試用的替身)。
    public func deposit(_ amount: Money, into id: SavingsGoalID) async throws {
        if let failure { throw failure }
        deposits.append(Deposit(id: id, amount: amount))
        stored = stored.map { goal in
            guard goal.id == id else { return goal }
            return SavingsGoal(
                id: id, name: goal.name, emoji: goal.emoji, targetAmount: goal.targetAmount,
                savedAmount: min(goal.savedAmount + amount, goal.targetAmount),
                monthlyReserve: goal.monthlyReserve, deadline: goal.deadline
            )
        }
    }

    public func delete(_ id: SavingsGoalID) async throws {
        if let failure { throw failure }
        deletedIDs.append(id)
        stored.removeAll { $0.id == id }
    }

    private static func goal(_ id: SavingsGoalID, from draft: SavingsGoalDraft, saved: Money) -> SavingsGoal {
        SavingsGoal(
            id: id, name: draft.name, emoji: draft.emoji, targetAmount: draft.targetAmount, savedAmount: saved,
            monthlyReserve: draft.monthlyReserve, deadline: draft.deadline
        )
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }
}
