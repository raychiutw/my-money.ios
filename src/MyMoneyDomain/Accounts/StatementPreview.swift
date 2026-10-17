/// 結帳日出帳預覽(`GET /accounts/:id/rollover-preview`,上游 ADR 0024):這一期結帳區間的全部消費與刷退，
/// 加上後端算好的基準值，讓畫面在使用者切換「延至下期」時就地試算，確認時才一次送出。
public struct StatementPreview: Hashable, Sendable {
    /// 結算區間的起訖日(後端算好,上游 ADR 0030):結帳日還沒到時是「上上期結帳日的次日到上期結帳日」，已到或已過是
    /// 「上期結帳日的次日到本月結帳日」。iOS 不自己推算區間。沒設結帳日的卡後端回 400，不會有預覽。
    public let startDate: CalendarDay
    public let endDate: CalendarDay
    /// 本月的結帳日還沒到(後端的 `statusLabel` 是 `before_statement`):這時結算的是上一期帳單。
    public let isStatementPending: Bool
    public let items: [StatementItem]
    /// 不在這期明細裡的已出帳消費減刷退(後端的 `baseNetBilled`)。
    public let baseNetBilled: Money
    /// 已沖抵已出帳待繳款的還款(後端的 `totalRepay`)。
    public let totalRepay: Money
    /// 不在這期明細裡的未出帳消費減刷退(後端的 `baseNetUnbilled`)。
    public let baseNetUnbilled: Money
    /// 不在這期明細裡的未出帳交易筆數(結帳日之後的新消費,後端的 `baseUnbilledCount`)。
    public let baseUnbilledCount: Int
    /// 這一期是不是已經做過出帳作業(有任何一筆已出帳)。
    public let hasRolledCycle: Bool
    /// 上期延入款的筆數(首次結算預設納入本期)。
    public let priorDeferredCount: Int

    public init(
        startDate: CalendarDay, endDate: CalendarDay, isStatementPending: Bool = false, items: [StatementItem],
        baseNetBilled: Money, totalRepay: Money, baseNetUnbilled: Money, baseUnbilledCount: Int = 0,
        hasRolledCycle: Bool = false, priorDeferredCount: Int = 0
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.isStatementPending = isStatementPending
        self.items = items
        self.baseNetBilled = baseNetBilled
        self.totalRepay = totalRepay
        self.baseNetUnbilled = baseNetUnbilled
        self.baseUnbilledCount = baseUnbilledCount
        self.hasRolledCycle = hasRolledCycle
        self.priorDeferredCount = priorDeferredCount
    }

    /// 開窗時就已經延至下期的明細(後端的 `is_initially_deferred`):上期延入款首次結算會被喚醒，所以不在裡面。
    public var initiallyDeferredIDs: Set<TransactionID> {
        Set(items.filter(\.isInitiallyDeferred).map(\.id))
    }

    /// 把 `deferring` 這些明細延至下期之後的結果。算式跟 web 一樣(上游 `Accounts.tsx`):後端沒有「假設延期」的端點，
    /// 所以這是本專案唯一在 client 端試算的地方(parity 刻意偏離)，基準值都用後端給的。
    public func outlook(deferring: Set<TransactionID>) -> StatementOutlook {
        let active = items.filter { !deferring.contains($0.id) }
        let expenses = active.filter { $0.kind == .expense }
        let refunds = active.filter { $0.kind == .refund }
        let expense = Self.sum(expenses)
        let refund = Self.sum(refunds)
        let net = max(expense - refund, .zero)
        // 公私拆解(後端 `calculateRolloverDebtBreakdown`):只有還沒報銷的公帳消費算家庭公帳代墊(已報銷、已額外處理的轉列個人私帳),
        // 公帳刷退優先折抵它;最小是 0。
        let pendingShared = Self.sum(expenses.filter { $0.householdPayment == .advancePending })
        let sharedRefund = Self.sum(refunds.filter(\.isShared))
        let shared = max(pendingShared - sharedRefund, .zero)
        let deferred = items.filter { deferring.contains($0.id) }
        let deferredNet = Self.signed(deferred)
        // 來源:交易日在區間內的是本期新增,早於起點的是上期延入;兩者都是固定值,不隨切換延期而變。
        let cycleItems = items.filter { $0.date >= startDate }
        let priorItems = items.filter { $0.date < startDate }
        return StatementOutlook(
            expense: expense, expenseCount: expenses.count, refund: refund, refundCount: refunds.count, net: net,
            sharedDebt: shared, personalDebt: max(net - shared, .zero),
            newInCycle: Self.signed(cycleItems), newInCycleCount: cycleItems.count,
            priorIncoming: Self.signed(priorItems), priorIncomingCount: priorItems.count, deferred: deferredNet,
            // 出帳後待繳款用「消費減刷退」(可以是負的)，不是出帳淨額,跟 web 一樣。
            projectedBilled: max(baseNetBilled + (expense - refund) - totalRepay, .zero),
            projectedUnbilled: max(baseNetUnbilled + deferredNet, .zero),
            deferredCount: deferred.count, baseUnbilledCount: baseUnbilledCount
        )
    }

    private static func sum(_ items: [StatementItem]) -> Money {
        items.reduce(.zero) { $0 + $1.amount }
    }

    /// 消費為正、刷退為負的淨額。
    private static func signed(_ items: [StatementItem]) -> Money {
        items.reduce(.zero) { $1.kind == .expense ? $0 + $1.amount : $0 - $1.amount }
    }
}

/// 出帳預覽的一筆明細:本期的一筆消費或刷退。
public struct StatementItem: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case expense
        case refund
    }

    public let id: TransactionID
    public let kind: Kind
    public let amount: Money
    public let date: CalendarDay
    public let category: TransactionCategory
    public let note: String
    public let isShared: Bool
    /// 公帳明細的支付來源與報銷狀態(上游 ADR 0029):待報銷、已撥款、已額外處理;不是公帳時是 `nil`。
    public let householdPayment: HouseholdPayment?
    /// 上期延入:交易日在上一個結帳日(含)之前、還沒出帳的款項。
    public let isPriorDeferred: Bool
    /// 開窗時是否已經延至下期。
    public let isInitiallyDeferred: Bool

    public init(
        id: TransactionID, kind: Kind, amount: Money, date: CalendarDay, category: TransactionCategory, note: String,
        isShared: Bool, householdPayment: HouseholdPayment? = nil, isPriorDeferred: Bool, isInitiallyDeferred: Bool
    ) {
        self.householdPayment = householdPayment
        self.id = id
        self.kind = kind
        self.amount = amount
        self.date = date
        self.category = category
        self.note = note
        self.isShared = isShared
        self.isPriorDeferred = isPriorDeferred
        self.isInitiallyDeferred = isInitiallyDeferred
    }
}

/// 切換延期後的試算結果。
public struct StatementOutlook: Hashable, Sendable {
    public let expense: Money
    public let expenseCount: Int
    public let refund: Money
    public let refundCount: Int
    /// 本期出帳淨額:消費減刷退，最小是 0。
    public let net: Money
    /// 本期出帳淨額裡的家庭公帳代墊。
    public let sharedDebt: Money
    public let personalDebt: Money
    /// 本期新增(交易日在結算區間內)的淨額與筆數:固定值，不隨切換延期而變。
    public let newInCycle: Money
    public let newInCycleCount: Int
    /// 上期延入(交易日早於區間起點)的淨額與筆數:固定值。
    public let priorIncoming: Money
    public let priorIncomingCount: Int
    /// 本次切換延至下期的淨額(消費減刷退)與筆數。
    public let deferred: Money
    /// 出帳後的已出帳待繳款。
    public let projectedBilled: Money
    /// 出帳後剩下的未出帳款。
    public let projectedUnbilled: Money
    /// 剩餘未出帳的筆數:結帳日之後的新消費加上本次延後的。
    public var remainingUnbilledCount: Int { baseUnbilledCount + deferredCount }
    public let deferredCount: Int
    let baseUnbilledCount: Int

    static let empty = StatementOutlook(
        expense: .zero, expenseCount: 0, refund: .zero, refundCount: 0, net: .zero, sharedDebt: .zero, personalDebt: .zero,
        newInCycle: .zero, newInCycleCount: 0, priorIncoming: .zero, priorIncomingCount: 0, deferred: .zero,
        projectedBilled: .zero, projectedUnbilled: .zero, deferredCount: 0, baseUnbilledCount: 0
    )
}
