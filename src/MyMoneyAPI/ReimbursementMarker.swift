import MyMoneyDomain

/// 後端 `reimbursement_id` 欄位的三種意思(上游 ADR 0027、`fe90634`):空(還沒報銷)、`EXTERNAL_SETTLED`(已額外處理)、
/// 其他是撥款流水的 ID。收支明細、出帳預覽、代墊統計三處都用它判斷，不各寫一份。
enum ReimbursementMarker: Equatable {
    case none
    case reimbursed(TransactionID)
    case handledSeparately

    init(_ raw: String?) {
        switch raw?.trimmingCharacters(in: .whitespaces) {
        case nil, "": self = .none
        case "EXTERNAL_SETTLED": self = .handledSeparately
        case let id?: self = .reimbursed(TransactionID(id))
        }
    }

    /// 公帳代墊的支付狀態(收支明細與出帳預覽的明細)。
    var payment: HouseholdPayment {
        switch self {
        case .none: .advancePending
        case .reimbursed: .advanceReimbursed
        case .handledSeparately: .advanceHandledSeparately
        }
    }
}
