/// 資產帳戶的 ID,由後端產生。
public struct AccountID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 資產帳戶(Account):現金錢包、銀行存款帳戶或信用卡帳戶。欄位不同，所以各自一個型別。
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

    public var kind: AccountKind {
        switch self {
        case .cash: .cash
        case .bank: .bank
        case .creditCard: .creditCard
        }
    }

    /// 帳戶擁有者(後端的 `user_id`:個人私帳是本人，家庭共同帳戶是建立者);資料沒有時是 `nil`。
    public var ownerID: UserID? {
        switch self {
        case .cash(let wallet): wallet.ownerID
        case .bank(let account): account.ownerID
        case .creditCard(let card): card.ownerID
        }
    }

    /// 歸屬家庭共同基金(信用卡叫家庭信用卡)或個人私帳。
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

    /// 目前的餘額(帳戶頁叫「現金錢包餘額」)。
    public let balance: Money

    /// 是否歸屬家庭共同基金(例如客廳零用金盒)。預設是個人私帳。
    public let isJointFund: Bool

    /// 擁有者(後端的 `user_id`)，判斷誰能編輯、刪除(上游 ADR 0013);資料沒有時是 `nil`。
    public let ownerID: UserID?

    public init(id: AccountID, name: String, colorHex: String, balance: Money, isJointFund: Bool, ownerID: UserID? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
        self.ownerID = ownerID
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

    /// 擁有者(後端的 `user_id`)，判斷誰能編輯、刪除(上游 ADR 0013);資料沒有時是 `nil`。
    public let ownerID: UserID?

    public init(id: AccountID, name: String, colorHex: String, balance: Money, isJointFund: Bool, ownerID: UserID? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.balance = balance
        self.isJointFund = isJointFund
        self.ownerID = ownerID
    }
}

/// 信用卡帳戶(Credit Card)。
public struct CreditCard: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let name: String
    public let colorHex: String

    /// 已出帳待繳款(Billed Debt)。後端的欄位叫 `balance`。
    public let billedDebt: Money

    /// 未出帳款(Unbilled Debt)。
    public let unbilledDebt: Money

    /// 信用額度;沒有設定時是 `nil`。
    public let creditLimit: Money?

    /// 結帳日(每月幾號);沒有設定時是 `nil`。
    public let statementDay: Int?

    /// 繳款日(每月幾號);沒有設定時是 `nil`。
    public let paymentDueDay: Int?

    /// 欠款公私拆解：信用卡待繳總額裡估算屬於家庭公帳的部分(後端用這張卡最近 50 筆支出估算)。
    public let sharedDebt: Money

    /// 欠款公私拆解：信用卡待繳總額裡估算屬於個人私帳的部分。
    public let personalDebt: Money

    /// 預設扣款帳戶(上游 `3d09060`):繳款時預設帶入的活存帳戶 ID 與名稱;沒綁定、舊的回應沒有欄位時是 `nil`。
    /// 綁定的活存帳戶被刪除後,後端還留著 ID、名稱是 `nil`(懸空):畫面當作沒綁定。
    public let paymentAccountID: AccountID?
    public let paymentAccountName: String?

    /// 欠款的雙層公私矩陣(上游 ADR 0025):已出帳與未出帳各自的公帳、私帳;後端回應沒有這幾個欄位時是 `nil`。
    public let debtMatrix: DebtMatrix?

    /// 是否歸屬家庭共同基金，也就是家庭信用卡(所有帳戶類型都能設歸屬)。
    public let isJointFund: Bool

    /// 持卡人(後端的 `user_id`):個人信用卡的還款沖銷、出帳作業、校準只有持卡人;資料沒有時是 `nil`。
    public let ownerID: UserID?

    /// 持卡人的名稱(後端的 `owner_name`);資料沒有時是 `nil`。
    public let ownerName: String?

    /// 他人的個人信用卡在公帳範圍經過脫敏(後端的 `is_masked`，上游 ADR 0015):沒有額度、已出帳 0、
    /// 未出帳款等於家庭代墊待繳額、個人消費 0，只有家庭代墊待繳額是真的。
    public let isMasked: Bool

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
        isJointFund: Bool = false,
        ownerID: UserID? = nil,
        ownerName: String? = nil,
        isMasked: Bool = false,
        debtMatrix: DebtMatrix? = nil,
        paymentAccountID: AccountID? = nil,
        paymentAccountName: String? = nil
    ) {
        self.paymentAccountID = paymentAccountID
        self.paymentAccountName = paymentAccountName
        self.debtMatrix = debtMatrix
        self.isJointFund = isJointFund
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.isMasked = isMasked
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

    /// 信用卡待繳總額：已出帳待繳款加上未出帳款。
    public var totalDue: Money {
        billedDebt + unbilledDebt
    }

    /// 剩餘額度：信用額度扣掉信用卡待繳總額，最小是 0;沒有信用額度(或額度是 0)時是 `nil`(web 在 `82d9124` 起的規則)。
    public var remainingCredit: Money? {
        guard let creditLimit, creditLimit > .zero else { return nil }
        return max(creditLimit - totalDue, .zero)
    }
}

/// 信用卡欠款的雙層公私矩陣(上游 ADR 0025):已出帳待繳款與未出帳款,各自拆成家庭公帳與個人私帳。
/// 全部是後端算好的值(共同基金的還款先沖已出帳公帳、溢出再沖未出帳公帳,後端處理);iOS 不自己加減。
public struct DebtMatrix: Hashable, Sendable {
    /// 已出帳公帳待繳款:當期帳單裡應由家庭共同基金繳納的部分。
    public let billedShared: Money
    /// 已出帳私帳待繳款:當期帳單裡持卡人自己繳的部分。
    public let billedPersonal: Money
    /// 未出帳公帳累計。
    public let unbilledShared: Money
    public let unbilledPersonal: Money

    public init(billedShared: Money, billedPersonal: Money, unbilledShared: Money, unbilledPersonal: Money) {
        self.billedShared = billedShared
        self.billedPersonal = billedPersonal
        self.unbilledShared = unbilledShared
        self.unbilledPersonal = unbilledPersonal
    }
}
