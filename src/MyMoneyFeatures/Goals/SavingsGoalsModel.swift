import Foundation
import MyMoneyDomain
import Observation

/// 儲蓄目標頁的 model(parity.md「儲蓄目標」)。
@MainActor
@Observable
public final class SavingsGoalsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var goals: [SavingsGoal] = []

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    @ObservationIgnored private let repository: any SavingsGoalRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var loadedVersion: Int?

    public init(repository: any SavingsGoalRepository, dataVersion: DataVersion) {
        self.repository = repository
        self.dataVersion = dataVersion
    }

    public var datedGoals: [SavingsGoal] { goals.filter { $0.deadline != nil } }
    public var undatedGoals: [SavingsGoal] { goals.filter { $0.deadline == nil } }

    public var totalSaved: Money { goals.reduce(.zero) { $0 + $1.savedAmount } }
    public var totalTarget: Money { goals.reduce(.zero) { $0 + $1.targetAmount } }
    public var totalMonthlyReserve: Money { goals.reduce(.zero) { $0 + $1.monthlyReserve } }

    /// 百分比固定用 `.` 當小數點(web 的 `toFixed`),不跟著裝置語系走。
    nonisolated fileprivate static let posix = Locale(identifier: "en_US_POSIX")

    /// 整體達成率，取 1 位小數;目標金額合計是 0 時顯示「0%」(跟 web 一樣)。
    public var overallRateText: String {
        guard totalTarget > .zero else { return "0%" }
        let rate = totalSaved.amount / totalTarget.amount * 100
        return "\(rate.formatted(.number.precision(.fractionLength(1)).rounded(rule: .toNearestOrAwayFromZero).locale(Self.posix)))%"
    }

    /// 載入儲蓄目標。重新載入時保留舊資料。
    public func load() async {
        let version = dataVersion.value
        do {
            goals = try await repository.goals()
            loadedVersion = version
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
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
        return "\(percent.formatted(.number.precision(.fractionLength(0)).rounded(rule: .toNearestOrAwayFromZero).locale(SavingsGoalsModel.posix)))%"
    }
}

/// 存入儲蓄目標的 sheet。存入**不會**動到任何資金帳戶。
@MainActor
@Observable
public final class SavingsGoalDepositModel {
    public var amountText = ""
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public let title: String
    /// 例如「目前已存 $3,000 / 目標 $60,000」。
    public let summary: String

    @ObservationIgnored private let goalID: SavingsGoalID
    @ObservationIgnored private let repository: any SavingsGoalRepository
    @ObservationIgnored private let dataVersion: DataVersion

    init(goal: SavingsGoal, repository: any SavingsGoalRepository, dataVersion: DataVersion) {
        title = "存入「\(goal.emoji) \(goal.name)」"
        summary = "目前已存 \(goal.savedAmount.formatted()) / 目標 \(goal.targetAmount.formatted())"
        goalID = goal.id
        self.repository = repository
        self.dataVersion = dataVersion
    }

    /// 存入;成功時回傳 `true`(sheet 關閉)並遞增資料版本。已存金額以後端重抓的結果為準。
    public func save() async -> Bool {
        errorMessage = nil
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            errorMessage = "請輸入有效存款金額"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deposit(Money(amount), into: goalID)
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "存錢失敗" : message
            return false
        }
        dataVersion.bump()
        return true
    }
}
