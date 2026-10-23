/// 家庭頁成員列右側 ⋯ 選單的項目(#274)。項目與順序由 `HouseholdModel.memberMenuItems` 決定，畫面只負責畫出來。
public enum MemberMenuItem: Hashable, Sendable {
    /// 進成員的代墊詳細頁。
    case details
    /// 沖銷:從共同基金撥款報銷(畫面上的動作叫「撥款報銷」「報銷沖帳」，選單裡簡稱沖銷)。
    case reimburse
    /// 標記處理:標記已額外處理(進詳細頁的勾選模式)。
    case markSettled
    /// 移除成員(破壞性，放最後)。
    case remove
}
