/// 交易記錄的 ID,由後端產生。
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

/// 交易記錄的分類。標準清單是支出 16 種、收入 8 種(上游 ADR-0009),外加 4 種系統專用的分類(「信用卡還款」等);
/// 機器人記帳或舊資料可能有清單以外的分類(例如「副業」),不遷移、照舊顯示,所以用字串保存。
public struct TransactionCategory: Hashable, Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public static let dining = TransactionCategory("餐飲")
    public static let salary = TransactionCategory("薪資")

    /// 信用卡扣款還款產生的交易記錄(銀行存款帳戶一筆支出、信用卡一筆收入);不能編輯或刪除，也不算進收支統計。
    public static let creditCardRepayment = TransactionCategory("信用卡還款")

    /// 帳戶互轉(ATM 提款以外)產生的交易記錄，一筆支出一筆收入(`POST /accounts/transfer`)。
    public static let internalTransfer = TransactionCategory("內部轉帳")

    /// 從銀行存款帳戶轉到現金錢包的 ATM 提款。
    public static let atmWithdrawal = TransactionCategory("ATM提款")

    /// 從家庭共同基金撥款報銷代墊款(`POST /households/reimburse`)。
    public static let advanceReimbursement = TransactionCategory("公帳代墊報銷")

    /// 系統分類：後端受保護(PUT、DELETE 回 400),統計也都排除(`bd0507b`)。
    public static let systemCategories: Set<TransactionCategory> = [
        creditCardRepayment, internalTransfer, atmWithdrawal, advanceReimbursement,
    ]

    /// 支出的標準分類，順序與上游 `web/src/components/utils.ts` 的 `CATEGORIES.expense` 一致。
    public static let expenseCategories = [
        "餐飲", "交通", "汽機車輛", "居家水電", "數位訂閱", "購物", "生活", "娛樂",
        "美妝保養", "醫療", "教育", "寵物毛孩", "旅行度假", "社交人情", "保險稅費", "其他",
    ].map(TransactionCategory.init)

    /// 收入的標準分類，順序與上游 `CATEGORIES.income` 一致。
    public static let incomeCategories = [
        "薪資", "獎金", "投資", "兼職", "政府補貼", "禮金餽贈", "二手出清", "其他",
    ].map(TransactionCategory.init)
}

/// 視角：瀏覽交易記錄與統計時的範圍(CONTEXT.md)。raw value 是後端的 `scope`。
public enum ViewScope: String, CaseIterable, Hashable, Sendable {
    /// 我的家庭公帳與個人私帳，加上家人的家庭公帳。
    case all
    /// 全家人的家庭公帳。
    case household
    /// 我記的所有交易記錄，包含家庭公帳與個人私帳。
    case personal
}

/// 交易記錄(Transaction)。
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

    /// 記帳人的 ID。用來判斷是不是自己記的：自己記的不顯示記帳人(#72)。
    public let recorderID: UserID?

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
        recorderName: String?,
        recorderID: UserID? = nil
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
        self.recorderID = recorderID
    }

    /// 系統內部平帳或轉帳的紀錄(4 種系統分類):後端禁止編輯和刪除，統計也都排除。
    public var isSystemRecord: Bool {
        TransactionCategory.systemCategories.contains(category)
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
