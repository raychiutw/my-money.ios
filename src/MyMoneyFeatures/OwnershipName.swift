import MyMoneyDomain
/// 歸屬與範圍的名稱：全 app 只有這一套說法(CONTEXT.md「家庭公帳／個人私帳」，#150)。
/// 上游 ADR 0014 用短名「公帳」「私帳」,iOS 依使用者要求一律寫完整名稱(`docs/parity.md` 偏離表)。
public enum OwnershipName {
    public static let household = "家庭公帳"
    public static let personal = "個人私帳"

    /// 資產帳戶或交易記錄的歸屬：家庭公帳（`isShared`）或個人私帳。
    public static func title(isShared: Bool) -> String { isShared ? household : personal }

    /// 交易記錄的歸屬，家庭公帳再依支付來源與報銷狀態分三態(上游 `d0424df`):
    /// 「家庭公帳」(共同帳戶直接扣款)、「家庭公帳・待報銷」、「家庭公帳・已撥款」。狀態未知時只寫「家庭公帳」。
    public static func title(isShared: Bool, payment: HouseholdPayment?) -> String {
        guard isShared else { return personal }
        switch payment {
        case nil, .jointFund: return household
        case .advancePending: return "\(household)・\(Terms.pendingReimbursement)"
        case .advanceReimbursed: return "\(household)・\(Terms.reimbursedPayout)"
        }
    }
}
