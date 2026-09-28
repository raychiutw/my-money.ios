/// 交易紀錄的 ID,由後端產生。
public struct TransactionID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 收入或支出。
public enum TransactionType: String, Hashable, Sendable {
    case income
    case expense
}

/// 交易紀錄的分類。固定清單是支出 8 種、收入 5 種，外加系統專用的「信用卡還款」;
/// 機器人記帳可能寫入清單以外的分類，所以用字串保存。
public struct TransactionCategory: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public static let dining = TransactionCategory("餐飲")
    public static let salary = TransactionCategory("薪資")

    /// 信用卡還款沖銷產生的交易紀錄;不能編輯或刪除，也不算進生活消費支出。
    public static let creditCardRepayment = TransactionCategory("信用卡還款")

    public static let expenseCategories = ["餐飲", "交通", "娛樂", "購物", "生活", "醫療", "教育", "其他"].map(TransactionCategory.init)
    public static let incomeCategories = ["薪資", "獎金", "投資", "兼職", "其他"].map(TransactionCategory.init)
}

/// 視角：瀏覽交易紀錄與統計時的範圍(CONTEXT.md)。raw value 是後端的 `scope`。
public enum ViewScope: String, CaseIterable, Hashable, Sendable {
    /// 我的家庭公帳與個人私帳，加上家人的家庭公帳。
    case all
    /// 全家人的家庭公帳。
    case household
    /// 我記的所有交易紀錄，包含家庭公帳與個人私帳。
    case personal
}

/// 交易紀錄(Transaction)。
public struct Transaction: Hashable, Sendable, Identifiable {
    public let id: TransactionID
    public let accountID: AccountID
    public let accountName: String?
    public let type: TransactionType
    public let category: TransactionCategory
    public let amount: Money
    public let note: String
    public let date: CalendarDay

    /// 家庭公帳是 `true`,個人私帳是 `false`。
    public let isShared: Bool

    /// 記帳人的名稱。
    public let recorderName: String?

    public init(
        id: TransactionID,
        accountID: AccountID,
        accountName: String?,
        type: TransactionType,
        category: TransactionCategory,
        amount: Money,
        note: String,
        date: CalendarDay,
        isShared: Bool,
        recorderName: String?
    ) {
        self.id = id
        self.accountID = accountID
        self.accountName = accountName
        self.type = type
        self.category = category
        self.amount = amount
        self.note = note
        self.date = date
        self.isShared = isShared
        self.recorderName = recorderName
    }

    /// 信用卡還款沖銷產生的紀錄。
    public var isCreditCardRepayment: Bool {
        category == .creditCardRepayment
    }
}

/// 記一筆時送出的內容。
public struct TransactionDraft: Hashable, Sendable {
    public var accountID: AccountID
    public var type: TransactionType
    public var category: TransactionCategory
    public var amount: Money
    public var note: String
    public var date: CalendarDay
    public var isShared: Bool

    public init(
        accountID: AccountID,
        type: TransactionType,
        category: TransactionCategory,
        amount: Money,
        note: String,
        date: CalendarDay,
        isShared: Bool
    ) {
        self.accountID = accountID
        self.type = type
        self.category = category
        self.amount = amount
        self.note = note
        self.date = date
        self.isShared = isShared
    }
}
