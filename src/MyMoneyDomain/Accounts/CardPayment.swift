/// 信用卡扣款還款的內容：從銀行存款帳戶扣款，先沖已出帳待繳款，不足的部分再沖未出帳款。
/// 後端會建立兩筆分類為「信用卡還款」的交易記錄：銀行存款帳戶一筆支出、信用卡一筆收入(`da82a11` 起)。
public struct CardPayment: Hashable, Sendable {
    public let bankAccountID: AccountID
    public let creditCardID: AccountID
    public let amount: Money
    public let date: CalendarDay
    public let note: String
    /// 這兩筆「信用卡還款」交易記錄是家庭公帳還是個人私帳。
    public let isShared: Bool

    public init(bankAccountID: AccountID, creditCardID: AccountID, amount: Money, date: CalendarDay, note: String, isShared: Bool) {
        self.bankAccountID = bankAccountID
        self.creditCardID = creditCardID
        self.amount = amount
        self.date = date
        self.note = note
        self.isShared = isShared
    }
}
