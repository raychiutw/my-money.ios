/// 信用卡還款沖銷的內容：從銀行存款帳戶扣款，先沖已出帳待繳金額，不足的部分再沖未出帳金額。
/// 後端會建立一筆分類為「信用卡還款」的交易紀錄。
public struct CardPayment: Hashable, Sendable {
    public let bankAccountID: AccountID
    public let creditCardID: AccountID
    public let amount: Money
    public let date: CalendarDay
    public let note: String
    /// 這筆「信用卡還款」交易紀錄是家庭公帳還是個人私帳。
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
