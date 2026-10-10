import Foundation
import MyMoneyDomain
import Observation

/// 建立或編輯儲蓄目標的 sheet(parity.md「儲蓄目標」)。
@MainActor
@Observable
public final class SavingsGoalEditorModel: Submitting {
    public var icon = SavingsGoalIcon.default
    public var name = ""
    public var targetAmountText = ""
    /// 選填;沒填時是 0。
    public var monthlyReserveText = ""
    /// 關掉等於沒有截止日;編輯時關掉就是移除截止日。
    public var hasDeadline = false
    /// 打開截止日時的日期;原本沒有截止日時預設今天。
    public var deadline: CalendarDay

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    public let title: String

    @ObservationIgnored private let editingID: SavingsGoalID?
    @ObservationIgnored private let repository: any SavingsGoalRepository
    @ObservationIgnored private let dataVersion: DataVersion

    public init(
        adding: Void,
        repository: any SavingsGoalRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        title = "建立儲蓄目標"
        editingID = nil
        deadline = today()
        self.repository = repository
        self.dataVersion = dataVersion
    }

    public init(
        editing goal: SavingsGoal,
        repository: any SavingsGoalRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        title = "編輯儲蓄目標"
        editingID = goal.id
        icon = goal.icon
        name = goal.name
        targetAmountText = "\(goal.targetAmount.amount)"
        monthlyReserveText = "\(goal.monthlyReserve.amount)"
        hasDeadline = goal.deadline != nil
        deadline = goal.deadline ?? today()
        self.repository = repository
        self.dataVersion = dataVersion
    }

    /// 儲存;成功時回傳 `true`(sheet 關閉)並遞增資料版本。
    public func save() async -> Bool {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "請輸入目標名稱"
            return false
        }
        guard let target = positiveAmount(targetAmountText, label: "目標金額") else { return false }
        // 跟 web 一樣：沒填或看不懂時當作 0;web 的欄位也不允許負數。
        let reserve = Money(wholeNumber: monthlyReserveText) ?? .zero
        let draft = SavingsGoalDraft(
            name: trimmedName, icon: icon, targetAmount: target, monthlyReserve: reserve,
            deadline: hasDeadline ? deadline : nil
        )
        guard await submitting(failure: "儲存失敗", {
            if let editingID {
                try await repository.update(editingID, with: draft)
            } else {
                try await repository.create(draft)
            }
        }) != nil else { return false }
        dataVersion.bump()
        return true
    }
}
