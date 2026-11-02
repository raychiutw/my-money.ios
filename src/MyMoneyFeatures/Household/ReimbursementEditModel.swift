import Foundation
import MyMoneyDomain
import Observation

/// 編輯一筆撥款沖帳紀錄(上游 ADR 0031,#314):只能改金額、日期、備註;收款帳戶與類型不變。
/// 金額改得比已結清代墊明細合計少時,後端回 400,訊息顯示在表單裡。
@MainActor
@Observable
public final class ReimbursementEditModel: Submitting {
    public var amountText: String
    public var date: CalendarDay
    public var note: String
    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    public let title: String

    @ObservationIgnored private let commit: @MainActor (Money, CalendarDay, String) async throws -> Void

    init(item: ReimbursementItem, memberName: String, commit: @escaping @MainActor (Money, CalendarDay, String) async throws -> Void) {
        amountText = "\(item.amount.amount)"
        date = item.date
        note = item.note
        title = "編輯\(memberName)的報銷紀錄"
        self.commit = commit
    }

    /// 儲存;成功時回傳 `true`(sheet 關閉)。
    public func save() async -> Bool {
        errorMessage = nil
        guard let amount = positiveAmount(amountText, label: "報銷金額") else { return false }
        let (date, note) = (date, note.trimmingCharacters(in: .whitespacesAndNewlines))
        return await submitting(failure: "操作失敗", { try await commit(amount, date, note) }) != nil
    }
}
