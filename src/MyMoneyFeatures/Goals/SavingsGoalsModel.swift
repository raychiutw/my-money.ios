import Foundation
import MyMoneyDomain
import Observation

/// 儲蓄目標頁的 model(parity.md「儲蓄目標」)。
@MainActor
@Observable
public final class SavingsGoalsModel {
    public typealias Phase = LoadPhase

    public private(set) var phase: Phase = .loading
    public private(set) var goals: [SavingsGoal] = []

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    @ObservationIgnored private let repository: any SavingsGoalRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var freshness = LoadFreshness<Unscoped>()

    /// 畫面的 `.task(id:)` 與 `refreshIfStale()` 共用的重載鍵:資料版本變了就要重載。
    public var reloadKey: ReloadKey<Unscoped> { ReloadKey(version: dataVersion.value) }
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let defaults: UserDefaults

    /// 骨架屏兩區的筆數(#204 核對):有截止日、沒有截止日;第一次沒有記錄時各 1。
    public struct SkeletonCounts: Equatable, Sendable {
        public let dated: Int
        public let undated: Int

        public init(dated: Int, undated: Int) {
            self.dated = dated
            self.undated = undated
        }
    }

    private var skeletonMemory: SkeletonShapeMemory { SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.goals") }

    public var skeletonCounts: SkeletonCounts {
        SkeletonCounts(dated: skeletonMemory.count(for: "dated", default: 1), undated: skeletonMemory.count(for: "undated", default: 1))
    }

    /// `locale` 決定日期的格式，預設跟著系統;`today` 決定截止日要不要寫年份。
    public init(
        repository: any SavingsGoalRepository,
        dataVersion: DataVersion,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.defaults = defaults
        self.repository = repository
        self.dataVersion = dataVersion
        self.locale = locale
        self.today = today
    }

    /// 截止日，例如「2027年3月31日」,今年的省略年份(DESIGN.md「日期」);沒有截止日是 `nil`。
    public func deadlineText(of goal: SavingsGoal) -> String? {
        goal.deadline?.text(today: today(), locale: locale)
    }

    public var datedGoals: [SavingsGoal] { goals.filter { $0.deadline != nil } }
    public var undatedGoals: [SavingsGoal] { goals.filter { $0.deadline == nil } }

    public var totalSaved: Money { SavingsGoalTotals(goals).saved }
    public var totalTarget: Money { SavingsGoalTotals(goals).target }
    public var totalMonthlyReserve: Money { SavingsGoalTotals(goals).monthlyReserve }

    /// 整體達成率,取 1 位小數;目標金額合計是 0 時顯示「0%」(跟 web 一樣)。
    public var overallRateText: String { SavingsGoalTotals(goals).overallRateText }

    /// 載入儲蓄目標。重新載入時保留舊資料。
    public func load() async {
        let key = reloadKey
        do {
            goals = try await repository.goals()
            freshness.markLoaded(key)
            skeletonMemory.record(count: datedGoals.count, for: "dated")
            skeletonMemory.record(count: undatedGoals.count, for: "undated")
            phase = .loaded
        } catch {
            phase = .failure(error)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard freshness.isStale(reloadKey) else { return }
        await load()
    }

    public func deleteConfirmation(for goal: SavingsGoal) -> String {
        "確定要刪除儲蓄目標「\(goal.name)」嗎？"
    }

    /// 刪除;成功後遞增資料版本。
    public func delete(_ goal: SavingsGoal) async {
        do {
            try await repository.delete(goal.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    public func makeEditor() -> SavingsGoalEditorModel {
        SavingsGoalEditorModel(adding: (), repository: repository, dataVersion: dataVersion)
    }

    public func makeEditor(editing goal: SavingsGoal) -> SavingsGoalEditorModel {
        SavingsGoalEditorModel(editing: goal, repository: repository, dataVersion: dataVersion)
    }

    /// 已達成的目標不能再存入(`nil`)。
    public func makeDeposit(for goal: SavingsGoal) -> SavingsGoalDepositModel? {
        guard !goal.isAchieved else { return nil }
        return SavingsGoalDepositModel(goal: goal, repository: repository, dataVersion: dataVersion)
    }
}

extension SavingsGoal {
    /// 進度(0 到 1),給進度條用。
    public var progress: Double {
        guard targetAmount > .zero else { return 0 }
        return min(NSDecimalNumber(decimal: savedAmount.amount / targetAmount.amount).doubleValue, 1)
    }

    /// 卡片上的百分比，取整數，最多 100%。
    public var percentText: String {
        guard targetAmount > .zero else { return "0%" }
        let percent = min(savedAmount.amount / targetAmount.amount * 100, 100)
        return percent.percentText(fractionDigits: 0)
    }

    /// VoiceOver 把整列念成一句，例如「沖繩旅遊，已存 3,000 元，目標 60,000 元，達成 5%，截止日 2027年3月31日」。
    /// 畫面上百分比交給進度條，不另外寫(#77)。
    public func spokenText(deadline: String?) -> String {
        var parts = [name, "已存 \(savedAmount.spokenText)", "目標 \(targetAmount.spokenText)", "達成 \(percentText)"]
        if let deadline { parts.append("截止日 \(deadline)") }
        if isAchieved { parts.append("已達成目標") }
        return parts.joined(separator: "，")
    }
}

/// 存入儲蓄目標的 sheet。存入**不會**動到任何資產帳戶。
@MainActor
@Observable
public final class SavingsGoalDepositModel: Submitting {
    public var amountText = ""
    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    public let title: String
    /// 例如「目前已存 $3,000 / 目標 $60,000」。
    public let summary: String

    @ObservationIgnored private let goalID: SavingsGoalID
    @ObservationIgnored private let repository: any SavingsGoalRepository
    @ObservationIgnored private let dataVersion: DataVersion

    init(goal: SavingsGoal, repository: any SavingsGoalRepository, dataVersion: DataVersion) {
        title = "存入「\(goal.name)」"
        summary = "目前已存 \(goal.savedAmount.formatted()) / 目標 \(goal.targetAmount.formatted())"
        goalID = goal.id
        self.repository = repository
        self.dataVersion = dataVersion
    }

    /// 存入;成功時回傳 `true`(sheet 關閉)並遞增資料版本。已存金額以後端重抓的結果為準。
    public func save() async -> Bool {
        errorMessage = nil
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請輸入有效存款金額"
            return false
        }
        guard await submitting(failure: "存入失敗", {
            try await repository.deposit(amount, into: goalID)
        }) != nil else { return false }
        dataVersion.bump()
        return true
    }
}
