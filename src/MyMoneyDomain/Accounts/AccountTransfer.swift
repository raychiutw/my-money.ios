/// ATM 提款／帳戶互轉(`POST /accounts/transfer`):把錢從一個現金錢包或銀行存款帳戶移到另一個。
///
/// 後端會建立兩筆系統交易記錄(轉出一筆支出、轉入一筆收入):銀行存款帳戶轉到現金錢包是「ATM提款」,
/// 其他組合是「內部轉帳」。只是資金調度，不算生活消費。
public struct AccountTransfer: Hashable, Sendable {
    public let fromAccountID: AccountID
    public let toAccountID: AccountID
    public let amount: Money
    /// 台灣時間的日期;一律送出，因為後端沒帶時用 UTC 的今天。
    public let date: CalendarDay
    public let note: String

    public init(fromAccountID: AccountID, toAccountID: AccountID, amount: Money, date: CalendarDay, note: String) {
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.amount = amount
        self.date = date
        self.note = note
    }
}
