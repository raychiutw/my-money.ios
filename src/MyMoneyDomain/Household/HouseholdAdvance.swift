import Foundation
/// 一位成員的家庭公帳代墊統計(`GET /households/advances`),全部由後端算好。
///
/// 只有從個人帳戶(個人私帳、私卡、個人現金錢包，`is_joint = 0`)付的家庭公帳支出才算代墊;
/// 由家庭共同基金直接付的是家庭直接開銷，不算。累計全部期間，不分月份。
public struct HouseholdAdvance: Hashable, Sendable, Identifiable {
    public let memberID: UserID
    public let memberName: String
    public let totalAdvanced: Money
    public let totalReimbursed: Money
    /// 待報銷:待報銷明細的淨額加總(上游 ADR 0027;支出減公帳退款)。**可以是負的**:退款比待報銷的支出多，叫「公帳待抵扣」。
    public let pendingReimbursement: Money
    public let advanceItems: [AdvanceItem]
    public let reimbursementItems: [ReimbursementItem]
    /// 已結清明細:已報銷(對得到是哪一次撥款)或已額外處理的代墊。
    public let settledItems: [SettledAdvanceItem]
    /// 累計撥款裡有對應到明細的部分(共同基金撥款結清的明細加總;已額外處理的不算)。
    public let linkedReimbursed: Money
    /// 累計撥款裡沒對應到任何明細的部分:家庭基金溢撥／預收款，不會吞掉之後新增的代墊。
    public let unlinkedReimbursed: Money
    /// 撥款報銷時可以收款的帳戶(後端 `b1382f4`):這位成員個人私帳的銀行存款帳戶和現金錢包。
    public let receivingAccounts: [ReceivingAccount]

    public var id: UserID { memberID }

    /// 待報銷不大於 0:不能再撥款報銷。
    public var isSettled: Bool { pendingReimbursement <= .zero }

    /// 待報銷是負的:公帳退款比待報銷的支出多,留待之後的代墊自動沖抵(上游 ADR 0029),這時不能撥款報銷。
    public var isOffsetPending: Bool { pendingReimbursement < .zero }

    /// 結清這筆已結清明細的那一次撥款(報銷明細裡的那一筆);已額外處理的、或對不到時是 `nil`。
    public func reimbursementItem(settling settled: SettledAdvanceItem) -> ReimbursementItem? {
        guard case .reimbursed(let id) = settled.settlement else { return nil }
        return reimbursementItems.first { $0.id == id }
    }

    public init(
        memberID: UserID,
        memberName: String,
        totalAdvanced: Money,
        totalReimbursed: Money,
        pendingReimbursement: Money,
        advanceItems: [AdvanceItem],
        reimbursementItems: [ReimbursementItem],
        receivingAccounts: [ReceivingAccount] = [],
        settledItems: [SettledAdvanceItem] = [],
        linkedReimbursed: Money = .zero,
        unlinkedReimbursed: Money = .zero
    ) {
        self.settledItems = settledItems
        self.linkedReimbursed = linkedReimbursed
        self.unlinkedReimbursed = unlinkedReimbursed
        self.memberID = memberID
        self.memberName = memberName
        self.totalAdvanced = totalAdvanced
        self.totalReimbursed = totalReimbursed
        self.pendingReimbursement = pendingReimbursement
        self.advanceItems = advanceItems
        self.reimbursementItems = reimbursementItems
        self.receivingAccounts = receivingAccounts
    }
}

/// 可收款帳戶：撥款報銷時，收款成員可以收款的個人私帳帳戶。
///
/// 後端只揭露名稱和類型，不含餘額，保護其他成員個人私帳的隱私。
public struct ReceivingAccount: Hashable, Sendable, Identifiable {
    public let id: AccountID
    public let name: String
    /// 只會是銀行存款帳戶或現金錢包。
    public let kind: AccountKind

    public init(id: AccountID, name: String, kind: AccountKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// 代墊明細的方向:成員用個人帳戶付的公帳支出,或個人帳戶收到的公帳退款／刷退(上游 ADR 0027:退款以負項抵扣待報銷總額)。
public enum AdvanceKind: Hashable, Sendable {
    case expense
    case refund
}

/// 一筆已結清的代墊明細怎麼結清的。
public enum AdvanceSettlement: Hashable, Sendable {
    /// 由某一次共同基金撥款報銷結清(報銷明細的 ID)。
    case reimbursed(TransactionID)
    /// 已額外處理(上游 `fe90634`):移出待報銷，沒有撥款流水、不動共同基金。
    case handledSeparately
}

public struct SettledAdvanceItem: Hashable, Sendable, Identifiable {
    public let item: AdvanceItem
    public let settlement: AdvanceSettlement

    public var id: TransactionID { item.id }

    public init(item: AdvanceItem, settlement: AdvanceSettlement) {
        self.item = item
        self.settlement = settlement
    }
}

/// 代墊明細的一筆：成員用個人帳戶付的家庭公帳支出(或收到的公帳退款)。
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
    /// 記錄時間(後端 `created_at`,#207);舊回應沒有時是 `nil`。
    public let recordedAt: Date?
    /// 支出或公帳退款;舊的回應沒有類型時是支出。
    public let kind: AdvanceKind
    /// 信用卡出帳狀態(上游 ADR 0029):只有扣款帳戶是信用卡時有;舊的回應沒有旗標時是未出帳。
    public let billing: BillingStatus?

    public init(
        id: TransactionID, date: CalendarDay, category: TransactionCategory, note: String, amount: Money,
        accountName: String, accountKind: AccountKind?, recordedAt: Date? = nil,
        kind: AdvanceKind = .expense, billing: BillingStatus? = nil
    ) {
        self.kind = kind
        self.billing = billing
        self.recordedAt = recordedAt
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
    /// 記錄時間(後端 `created_at`,#207);舊回應沒有時是 `nil`。
    public let recordedAt: Date?

    public init(id: TransactionID, date: CalendarDay, amount: Money, note: String, accountName: String, recordedAt: Date? = nil) {
        self.recordedAt = recordedAt
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
        self.accountName = accountName
    }
}

/// 從家庭共同基金撥款報銷代墊款(`POST /households/reimburse`)。
///
/// 後端建立兩筆「公帳代墊報銷」系統交易記錄(共同基金一筆支出、收款帳戶一筆收入),不算家庭消費。
public struct Reimbursement: Hashable, Sendable {
    /// 收款的成員。
    public let memberID: UserID
    /// 撥款的家庭共同基金(歸屬家庭共同基金的銀行存款帳戶或現金錢包)。
    public let fromAccountID: AccountID
    /// 收款成員的個人帳戶。
    public let toAccountID: AccountID
    public let amount: Money
    /// 台灣時間的日期;一律送出，因為後端沒帶時用 UTC 的今天。
    public let date: CalendarDay
    public let note: String
    /// 勾選要結清的代墊明細(上游 `d0424df`);空的時候後端依時間順序把最早的未結清代墊對齊到這筆報銷。
    public let advanceIDs: [TransactionID]

    public init(
        memberID: UserID, fromAccountID: AccountID, toAccountID: AccountID, amount: Money, date: CalendarDay, note: String,
        advanceIDs: [TransactionID] = []
    ) {
        self.advanceIDs = advanceIDs
        self.memberID = memberID
        self.fromAccountID = fromAccountID
        self.toAccountID = toAccountID
        self.amount = amount
        self.date = date
        self.note = note
    }
}
