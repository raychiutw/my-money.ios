/// 資金帳戶的兩種類型。
public enum AccountKind: Hashable, Sendable {
    case bank
    case creditCard
}

/// 新增或編輯時送出的資金帳戶內容。依類型分成兩種形狀：銀行存款帳戶沒有信用額度與日期。
public enum AccountDraft: Hashable, Sendable {
    case bank(BankAccountDraft)
    case creditCard(CreditCardDraft)
}

public struct BankAccountDraft: Hashable, Sendable {
    public var name: String
    public var colorHex: String
    public var balance: Money

    /// 家庭共同基金的標記。編輯時要保留原本的值(後端的 PUT 沒收到會寫成 0)。
    public var isJointFund: Bool

    public init(name: String, colorHex: String, balance: Money, isJointFund: Bool) {
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
    }
}

public struct CreditCardDraft: Hashable, Sendable {
    public var name: String
    public var colorHex: String
    public var billedDebt: Money
    public var unbilledDebt: Money
    public var creditLimit: Money?
    public var statementDay: Int?
    public var paymentDueDay: Int?

    public init(
        name: String,
        colorHex: String,
        billedDebt: Money,
        unbilledDebt: Money,
        creditLimit: Money?,
        statementDay: Int?,
        paymentDueDay: Int?
    ) {
        self.name = name
        self.colorHex = colorHex
        self.billedDebt = billedDebt
        self.unbilledDebt = unbilledDebt
        self.creditLimit = creditLimit
        self.statementDay = statementDay
        self.paymentDueDay = paymentDueDay
    }
}
