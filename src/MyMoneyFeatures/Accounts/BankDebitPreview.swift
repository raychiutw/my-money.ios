import MyMoneyDomain

/// 活存帳戶的待扣卡費預覽(上游 `3d09060`):綁在這個活存帳戶、等著從它扣款的信用卡,彙總已出帳與總待繳,
/// 以及扣掉之後的餘額,餘額不夠扣已出帳時標示不足。
///
/// 是 web 在前端做的簡單加減(後端沒有彙總端點),全部用後端給的卡片數字——顯示用的算術,不是業務規則重算(`docs/parity.md`)。
/// **脫敏的他人私卡不計入**(它的綁定是對方的私人設定,`balance` 也只是已出帳公帳):由呼叫端先濾掉(判斷來源是權限，只在一處);
/// 這裡只算呼叫端給的卡(目前帳戶範圍載入的)。
public struct BankDebitPreview: Hashable, Sendable {
    public let cardCount: Int
    /// 已出帳待扣款:綁定的卡的已出帳待繳款合計,代表即將到期扣款的確定負債。
    public let billed: Money
    /// 含未出帳的總待繳。
    public let total: Money
    public let balanceAfterBilled: Money

    /// 存款不夠扣已出帳(扣後為負;剛好扣完不算)。只有總待繳不夠不警示:未出帳還沒到扣款日。
    public var isShortOfBilled: Bool { balanceAfterBilled < .zero }

    public var shortfall: Money { max(.zero - balanceAfterBilled, .zero) }

    /// 例如「待扣卡費 2 張・已出帳 $4,000・含未出帳 $4,500」。
    public var summaryText: String {
        "待扣卡費 \(cardCount) 張・已出帳 \(billed.formatted())・含未出帳 \(total.formatted())"
    }

    /// 例如「扣已出帳後餘額 $1,000」。
    public var balanceText: String { "扣已出帳後餘額 \(balanceAfterBilled.formatted())" }

    /// 存款不足時的警示,例如「存款不足扣繳已出帳，差 $1,000」;夠扣時是 `nil`。
    public var warningText: String? {
        isShortOfBilled ? "存款不足扣繳已出帳，差 \(shortfall.formatted())" : nil
    }

    /// VoiceOver 念的整句(不念符號)。
    public var spokenText: String {
        let base = "待扣卡費 \(cardCount) 張，已出帳 \(billed.spokenText)，含未出帳 \(total.spokenText)，扣已出帳後餘額 \(balanceAfterBilled.spokenText)"
        return isShortOfBilled ? "\(base)，存款不足扣繳已出帳，差 \(shortfall.spokenText)" : base
    }

    /// 卡片金額下面的小字:彙總、扣後餘額、不足時的警示(紅色)。
    public var notes: [CardNote] {
        [CardNote(text: summaryText), CardNote(text: balanceText, isWarning: isShortOfBilled)]
            + (warningText.map { [CardNote(text: $0, isWarning: true)] } ?? [])
    }

    /// 沒有任何卡綁在這個活存帳戶時是 `nil`(帳戶列維持原樣)。`cards` 要先濾掉脫敏的他人私卡。
    public static func make(for bank: BankAccount, cards: [CreditCard]) -> BankDebitPreview? {
        let bound = cards.filter { $0.paymentAccountID == bank.id }
        guard !bound.isEmpty else { return nil }
        let billed = bound.reduce(Money.zero) { $0 + $1.billedDebt }
        let total = bound.reduce(Money.zero) { $0 + $1.totalDue }
        return BankDebitPreview(
            cardCount: bound.count, billed: billed, total: total,
            balanceAfterBilled: bank.balance - billed
        )
    }
}
