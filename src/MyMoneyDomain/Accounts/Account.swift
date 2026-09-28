/// 資金帳戶的 ID,由後端產生。
public struct AccountID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 資金帳戶(Account):現金錢包、銀行存款帳戶或信用卡帳戶。欄位不同，所以各自一個型別。
public enum Account: Hashable, Sendable, Identifiable {
    case cash(CashWallet)
    case bank(BankAccount)
    case creditCard(CreditCard)

    public var id: AccountID {
        switch self {
        case .cash(let wallet): wallet.id
        case .bank(let account): account.id
        case .creditCard(let card): card.id
        }
    }

    public var name: String {
        switch self {
        case .cash(let wallet): wallet.name
        case .bank(let account): account.name
        case .creditCard(let card): card.name
        }
    }

    /// 家庭公用(家庭共同基金、家庭卡)或個人私帳。
    public var isJointFund: Bool {
        switch self {
        case .cash(let wallet): wallet.isJointFund
        case .bank(let account): account.isJointFund
        case .creditCard(let card): card.isJointFund
        }
    }
}

/// 現金錢包(Cash Wallet):存放實體現鈔的正資產，例如皮夾、客廳零用金盒。
public struct CashWallet: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let name: String

    /// 使用者選的代表色，例如 `#10B981`。
    public let colorHex: String

    /// 目前的現金餘額。
    public let balance: Money

    /// 是否標記為家庭公用(例如客廳零用金盒)。預設是個人私帳。
    public let isJointFund: Bool

    public init(id: AccountID, name: String, colorHex: String, balance: Money, isJointFund: Bool) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
    }
}

/// 銀行存款帳戶(Bank Account):個人或共同持有的活期存款正資產帳戶。
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

    /// 欠款公私拆解：待繳卡費總額裡估算屬於家庭公帳的部分(後端用這張卡最近 50 筆支出估算)。
    public let sharedDebt: Money

    /// 欠款公私拆解：待繳卡費總額裡估算屬於個人私帳的部分。
    public let personalDebt: Money

    /// 是否標記為家庭卡(所有帳戶類型都能設歸屬)。
    public let isJointFund: Bool

    public init(
        id: AccountID,
        name: String,
        colorHex: String,
        billedDebt: Money,
        unbilledDebt: Money,
        creditLimit: Money?,
        statementDay: Int?,
        paymentDueDay: Int?,
        sharedDebt: Money = .zero,
        personalDebt: Money = .zero,
        isJointFund: Bool = false
    ) {
        self.isJointFund = isJointFund
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.billedDebt = billedDebt
        self.unbilledDebt = unbilledDebt
        self.creditLimit = creditLimit
        self.statementDay = statementDay
        self.paymentDueDay = paymentDueDay
        self.sharedDebt = sharedDebt
        self.personalDebt = personalDebt
    }

    /// 待繳卡費總額：已出帳待繳金額加上未出帳金額。
    public var totalDue: Money {
        billedDebt + unbilledDebt
    }

    /// 剩餘額度：信用額度扣掉待繳卡費總額，最小是 0;沒有信用額度(或額度是 0)時是 `nil`(web 在 `82d9124` 起的規則)。
    public var remainingCredit: Money? {
        guard let creditLimit, creditLimit > .zero else { return nil }
        return max(creditLimit - totalDue, .zero)
    }
}
