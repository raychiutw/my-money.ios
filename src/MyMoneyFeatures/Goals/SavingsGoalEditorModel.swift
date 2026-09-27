import Foundation
import MyMoneyDomain
import Observation

/// 建立或編輯儲蓄目標的 sheet(parity.md「儲蓄目標」)。
@MainActor
@Observable
public final class SavingsGoalEditorModel {
    /// 跟 web 一樣的 12 種 emoji,第一個是預設值。
    public static let emojiChoices = ["🎯", "✈️", "🏠", "🚗", "💍", "💻", "👶", "🎓", "🏥", "🏖️", "🎒", "🎨"]

    public var emoji = emojiChoices[0]
    public var name = ""
    public var targetAmountText = ""
    /// 選填;沒填時是 0。
    public var monthlyReserveText = ""
    /// 關掉等於沒有截止日;編輯時關掉就是移除截止日。
    public var hasDeadline = false
    /// 打開截止日時的日期;原本沒有截止日時預設今天。
    public var deadline: CalendarDay

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

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
        emoji = goal.emoji
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
        let posix = Locale(identifier: "en_US_POSIX")
        guard let target = Decimal(string: targetAmountText, locale: posix), target > 0 else {
            errorMessage = "請輸入有效目標金額"
            return false
        }
        // 跟 web 一樣：沒填或看不懂時當作 0;web 的欄位也不允許負數。
        let reserve = max(Decimal(string: monthlyReserveText, locale: posix) ?? 0, 0)
        let draft = SavingsGoalDraft(
            name: trimmedName, emoji: emoji, targetAmount: Money(target), monthlyReserve: Money(reserve),
            deadline: hasDeadline ? deadline : nil
        )
        isSaving = true
        defer { isSaving = false }
        do {
            if let editingID {
                try await repository.update(editingID, with: draft)
            } else {
                try await repository.create(draft)
            }
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "儲存失敗" : message
            return false
        }
        dataVersion.bump()
        return true
    }
}
