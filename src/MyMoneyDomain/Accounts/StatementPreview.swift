/// 結帳日出帳預覽(`GET /accounts/:id/rollover-preview`,上游 ADR 0024):這一期結帳區間的全部消費與刷退，
/// 加上後端算好的基準值，讓畫面在使用者切換「延至下期」時就地試算，確認時才一次送出。
public struct StatementPreview: Hashable, Sendable {
    /// 本期結帳區間的終點；卡沒有設結帳日時是 `nil`(後端不分期，所有未出帳的都算)。
    public let statementDate: CalendarDay?
    /// 上一個結帳日；區間是它的次日到 `statementDate`。沒有結帳日時是 `nil`。
    public let previousStatementDate: CalendarDay?
    public let items: [StatementItem]
    /// 不在這期明細裡的已出帳消費減刷退(後端的 `baseNetBilled`)。
    public let baseNetBilled: Money
    /// 已沖抵已出帳待繳款的還款(後端的 `totalRepay`)。
    public let totalRepay: Money
    /// 不在這期明細裡的未出帳消費減刷退(後端的 `baseNetUnbilled`)。
    public let baseNetUnbilled: Money
    /// 這一期是不是已經做過出帳作業(有任何一筆已出帳)。
    public let hasRolledCycle: Bool
    /// 上期延入款的筆數(首次結算預設納入本期)。
    public let priorDeferredCount: Int

    public init(
        statementDate: CalendarDay?, previousStatementDate: CalendarDay?, items: [StatementItem],
        baseNetBilled: Money, totalRepay: Money, baseNetUnbilled: Money,
        hasRolledCycle: Bool = false, priorDeferredCount: Int = 0
    ) {
        self.statementDate = statementDate
        self.previousStatementDate = previousStatementDate
        self.items = items
        self.baseNetBilled = baseNetBilled
        self.totalRepay = totalRepay
        self.baseNetUnbilled = baseNetUnbilled
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
        let expense = expenses.reduce(Money.zero) { $0 + $1.amount }
        let refund = refunds.reduce(Money.zero) { $0 + $1.amount }
        let net = max(expense - refund, .zero)
        let shared = expenses.filter(\.isShared).reduce(Money.zero) { $0 + $1.amount }
        let deferredNet = items.filter { deferring.contains($0.id) }.reduce(Money.zero) {
            $1.kind == .expense ? $0 + $1.amount : $0 - $1.amount
        }
        return StatementOutlook(
            expense: expense, expenseCount: expenses.count, refund: refund, refundCount: refunds.count, net: net,
            sharedDebt: shared, personalDebt: max(net - shared, .zero),
            // 出帳後待繳款用「消費減刷退」(可以是負的)，不是出帳淨額,跟 web 一樣。
            projectedBilled: max(baseNetBilled + (expense - refund) - totalRepay, .zero),
            projectedUnbilled: max(baseNetUnbilled + deferredNet, .zero),
            deferredCount: items.filter { deferring.contains($0.id) }.count
        )
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
    /// 上期延入:交易日在上一個結帳日(含)之前、還沒出帳的款項。
    public let isPriorDeferred: Bool
    /// 開窗時是否已經延至下期。
    public let isInitiallyDeferred: Bool

    public init(
        id: TransactionID, kind: Kind, amount: Money, date: CalendarDay, category: TransactionCategory, note: String,
        isShared: Bool, isPriorDeferred: Bool, isInitiallyDeferred: Bool
    ) {
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
    /// 出帳後的已出帳待繳款。
    public let projectedBilled: Money
    /// 出帳後剩下的未出帳款。
    public let projectedUnbilled: Money
    public let deferredCount: Int

}
