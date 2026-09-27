/// 資金帳戶的 ID,由後端產生。
public struct AccountID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 資金帳戶(Account):銀行存款帳戶或信用卡帳戶。兩種的欄位不同，所以分成兩個型別。
public enum Account: Hashable, Sendable, Identifiable {
    case bank(BankAccount)
    case creditCard(CreditCard)

    public var id: AccountID {
        switch self {
        case .bank(let account): account.id
        case .creditCard(let card): card.id
        }
    }

    public var name: String {
        switch self {
        case .bank(let account): account.name
        case .creditCard(let card): card.name
        }
    }
}

/// 銀行存款帳戶(Bank Account):現金、活存或數位帳戶。
public struct BankAccount: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let name: String

    /// 使用者選的代表色，例如 `#A8D8EA`。
    public let colorHex: String

    /// 目前持有的金額。
    public let balance: Money

    /// 是否標記為家庭共同基金(Joint Fund)。
    public let isJointFund: Bool

    public init(id: AccountID, name: String, colorHex: String, balance: Money, isJointFund: Bool) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
    }
}

/// 信用卡帳戶(Credit Card)。
public struct CreditCard: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let name: String
    public let colorHex: String

    /// 已出帳待繳金額(Billed Debt)。後端的欄位叫 `balance`。
    public let billedDebt: Money

    /// 未出帳金額(Unbilled Debt)。
    public let unbilledDebt: Money

    /// 信用額度;沒有設定時是 `nil`。
    public let creditLimit: Money?

    /// 結帳日(每月幾號);沒有設定時是 `nil`。
    public let statementDay: Int?

    /// 繳款日(每月幾號);沒有設定時是 `nil`。
    public let paymentDueDay: Int?

    public init(
        id: AccountID,
        name: String,
        colorHex: String,
        billedDebt: Money,
        unbilledDebt: Money,
        creditLimit: Money?,
        statementDay: Int?,
        paymentDueDay: Int?
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.billedDebt = billedDebt
        self.unbilledDebt = unbilledDebt
        self.creditLimit = creditLimit
        self.statementDay = statementDay
        self.paymentDueDay = paymentDueDay
    }

    /// 待繳卡費總額：已出帳待繳金額加上未出帳金額。
    public var totalDue: Money {
        billedDebt + unbilledDebt
    }

    /// 剩餘額度：信用額度扣掉待繳卡費總額;沒有信用額度時是 `nil`。
    public var remainingCredit: Money? {
        creditLimit.map { $0 - totalDue }
    }

    /// 剩餘額度低於 10,000 時要警示(web 的門檻，見 parity.md「帳戶」)。
    public var isLowOnCredit: Bool {
        guard let remainingCredit else { return false }
        return remainingCredit < Self.lowCreditThreshold
    }

    private static let lowCreditThreshold = Money(10000)
}
