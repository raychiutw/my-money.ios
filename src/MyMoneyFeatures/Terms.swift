/// 使用者看得見的詞(CONTEXT.md「iOS 用詞更名」、`docs/parity.md` 刻意偏離，#179、#181)：全 app 只有這一套說法，
/// 畫面、訊息、VoiceOver 都從這裡取，不各寫各的字串。上游 web 用的是左邊的詞(銀行存款帳戶、現金錢包、交易記錄、分攤平滑)。
///
/// 這些詞的 VoiceOver 念法跟畫面上寫的一樣，所以不另外放「念法」版本。
/// `TermsRulesTests` 掃描 `src/` 的字串常值，出現舊詞就失敗。
public enum Terms {
    /// 活存帳戶(上游:銀行存款帳戶)。
    public static let bankAccount = "活存帳戶"
    /// 現金(上游:現金錢包)。
    public static let cash = "現金"
    /// 記帳:功能的名字(tab、入口、返回目標)。「記一筆」「機器人記帳」是另外的詞，不受影響。
    public static let ledger = "記帳"
    /// 收支明細:記錄本身(列表標題、刪除確認、空狀態、CSV)。上游舊稱交易記錄。
    public static let transactions = "收支明細"
    /// 週期支出每月平均(上游舊稱:分攤平滑)。
    public static let expenseAmortization = "週期支出每月平均"
    /// 週期收入每月平均。
    public static let incomeAmortization = "週期收入每月平均"
    /// 換算每月平均:長週期的單一項目(年繳、季繳)換算成每月的金額(上游舊稱:換算月分攤平滑)。
    public static let monthlyAverage = "換算每月平均"
    /// 待報銷總額(上游舊稱:待報銷代墊總額)。
    public static let pendingReimbursementTotal = "待報銷總額"
    /// 報銷沖帳(上游舊稱:從共同基金一鍵報銷)。
    public static let reimburse = "報銷沖帳"
}
