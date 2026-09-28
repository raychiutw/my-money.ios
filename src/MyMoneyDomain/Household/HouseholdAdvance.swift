/// 一位成員的家庭公帳代墊統計(`GET /households/advances`),全部由後端算好。
///
/// 只有從個人帳戶(個人私帳、私卡、個人現金錢包，`is_joint = 0`)付的家庭公帳支出才算代墊;
/// 由家庭共同基金直接付的是家庭直接開銷，不算。累計全部期間，不分月份。
public struct HouseholdAdvance: Hashable, Sendable, Identifiable {
    public let memberID: UserID
    public let memberName: String
    public let totalAdvanced: Money
    public let totalReimbursed: Money
    /// 待報銷 = 累計代墊 − 已報銷，最小是 0。
    public let pendingReimbursement: Money
    public let advanceItems: [AdvanceItem]
    public let reimbursementItems: [ReimbursementItem]

    public var id: UserID { memberID }

    /// 待報銷是 0:「已全數結清」。
    public var isSettled: Bool { pendingReimbursement <= .zero }

    public init(
        memberID: UserID,
        memberName: String,
        totalAdvanced: Money,
        totalReimbursed: Money,
        pendingReimbursement: Money,
        advanceItems: [AdvanceItem],
        reimbursementItems: [ReimbursementItem]
    ) {
        self.memberID = memberID
        self.memberName = memberName
        self.totalAdvanced = totalAdvanced
        self.totalReimbursed = totalReimbursed
        self.pendingReimbursement = pendingReimbursement
        self.advanceItems = advanceItems
        self.reimbursementItems = reimbursementItems
    }
}

/// 代墊明細的一筆：成員用個人帳戶付的家庭公帳支出。
public struct AdvanceItem: Hashable, Sendable, Identifiable {
    public let id: TransactionID
    public let date: CalendarDay
    public let category: TransactionCategory
    public let note: String
    public let amount: Money
    /// 墊付的扣款帳戶;帳戶已刪除時後端補「個人帳戶」。
    public let accountName: String
    /// 扣款帳戶的類型;帳戶已刪除時是 `nil`。
    public let accountKind: AccountKind?

    public init(
        id: TransactionID, date: CalendarDay, category: TransactionCategory, note: String, amount: Money,
        accountName: String, accountKind: AccountKind?
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.note = note
        self.amount = amount
        self.accountName = accountName
        self.accountKind = accountKind
    }
}

/// 報銷明細的一筆：從家庭共同基金撥回這位成員個人帳戶的款項。
public struct ReimbursementItem: Hashable, Sendable, Identifiable {
    public let id: TransactionID
    public let date: CalendarDay
    public let amount: Money
    public let note: String
    /// 收款帳戶;帳戶已刪除時後端補「收款帳戶」。
    public let accountName: String

    public init(id: TransactionID, date: CalendarDay, amount: Money, note: String, accountName: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
        self.accountName = accountName
    }
}

/// 從家庭共同基金撥款報銷代墊款(`POST /households/reimburse`)。
///
/// 後端建立兩筆「公帳代墊報銷」系統交易紀錄(共同基金一筆支出、收款帳戶一筆收入),不算家庭消費。
public struct Reimbursement: Hashable, Sendable {
    /// 收款的成員。
    public let memberID: UserID
    /// 撥款的家庭共同基金(家庭公用帳戶)。
    public let fromAccountID: AccountID
    /// 收款成員的個人帳戶。
    public let toAccountID: AccountID
    public let amount: Money
    /// 台灣時間的日期;一律送出，因為後端沒帶時用 UTC 的今天。
    public let date: CalendarDay
    public let note: String

    public init(memberID: UserID, fromAccountID: AccountID, toAccountID: AccountID, amount: Money, date: CalendarDay, note: String) {
        self.memberID = memberID
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.amount = amount
        self.date = date
        self.note = note
    }
}
