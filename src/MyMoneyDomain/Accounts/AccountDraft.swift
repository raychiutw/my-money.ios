/// 資產帳戶的三種類型。
public enum AccountKind: Hashable, Sendable {
    case cash
    case bank
    case creditCard
}

/// 新增或編輯時送出的資產帳戶內容。依類型分成不同形狀：現金錢包和銀行存款帳戶沒有信用額度與日期。
public enum AccountDraft: Hashable, Sendable {
    case cash(CashWalletDraft)
    case bank(BankAccountDraft)
    case creditCard(CreditCardDraft)
}

public struct CashWalletDraft: Hashable, Sendable {
    public var name: String
    public var colorHex: String
    public var balance: Money

    /// 家庭共同基金的標記(預設個人私帳)。編輯時要保留原本的值(後端的 PUT 沒收到會寫成 0)。
    public var isJointFund: Bool

    public init(name: String, colorHex: String, balance: Money, isJointFund: Bool) {
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
    }
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

/// 信用卡預設扣款帳戶在新增或編輯時的意思(上游 `3d09060`):後端的 PUT 對「欄位沒送」是保留原值、對 `null` 才是清除。
public enum PaymentAccountSetting: Hashable, Sendable {
    /// 不動它:不送這個欄位(編輯時後端保留原值;新增時等於沒綁定)。
    case unchanged
    /// 使用者選了「不綁定」:送明確的 `null`(清除)。
    case none
    /// 綁定這個活存帳戶。
    case bank(AccountID)
}

public struct CreditCardDraft: Hashable, Sendable {
    public var name: String
    public var colorHex: String
    public var billedDebt: Money
    public var unbilledDebt: Money
    public var creditLimit: Money?
    public var statementDay: Int?
    public var paymentDueDay: Int?

    /// 家庭信用卡的標記。
    public var isJointFund: Bool

    /// 預設扣款帳戶(上游 `3d09060`,選填)。**三態**:`nil` 同時代表「使用者清除」與「呼叫端沒有這個資訊」會把看不到的綁定清掉,
    /// 所以分開——預設是 `.unchanged`(不送這個欄位,後端保留原值)。
    public var paymentAccount: PaymentAccountSetting

    public init(
        name: String,
        colorHex: String,
        billedDebt: Money,
        unbilledDebt: Money,
        creditLimit: Money?,
        statementDay: Int?,
        paymentDueDay: Int?,
        isJointFund: Bool = false,
        paymentAccount: PaymentAccountSetting = .unchanged
    ) {
        self.paymentAccount = paymentAccount
        self.isJointFund = isJointFund
        self.name = name
        self.colorHex = colorHex
        self.billedDebt = billedDebt
        self.unbilledDebt = unbilledDebt
        self.creditLimit = creditLimit
        self.statementDay = statementDay
        self.paymentDueDay = paymentDueDay
    }
}
