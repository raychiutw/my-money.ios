/// 家庭群組的資金指標(`GET /accounts/balance`),全部由後端算好。
public struct BalanceSummary: Hashable, Sendable {
    /// 所有現金錢包的餘額合計。
    public let cashTotal: Money

    /// 所有銀行存款帳戶的餘額合計。
    public let bankBalanceTotal: Money

    /// 所有信用卡帳戶的已出帳待繳金額合計。
    public let billedDebtTotal: Money

    /// 所有信用卡帳戶的未出帳金額合計。
    public let unbilledDebtTotal: Money

    /// 淨可用資產(Available Balance):現金 + 銀行存款 − 信用卡待繳，後端算好。
    public let availableBalance: Money

    /// 固定支出的週期攤提(每月)。
    public let monthlyAmortization: Money

    /// 儲蓄目標的每月預留合計。
    public let monthlySavingsReserve: Money

    /// 真實可支配現金(Disposable Cash)。
    public let disposableCash: Money

    public init(
        cashTotal: Money = .zero,
        bankBalanceTotal: Money,
        billedDebtTotal: Money,
        unbilledDebtTotal: Money,
        availableBalance: Money,
        monthlyAmortization: Money,
        monthlySavingsReserve: Money,
        disposableCash: Money
    ) {
        self.cashTotal = cashTotal
        self.bankBalanceTotal = bankBalanceTotal
        self.billedDebtTotal = billedDebtTotal
        self.unbilledDebtTotal = unbilledDebtTotal
        self.availableBalance = availableBalance
        self.monthlyAmortization = monthlyAmortization
        self.monthlySavingsReserve = monthlySavingsReserve
        self.disposableCash = disposableCash
    }

    /// 全部是 0(沒有任何資金帳戶時)。
    public static let zero = BalanceSummary(
        bankBalanceTotal: .zero,
        billedDebtTotal: .zero,
        unbilledDebtTotal: .zero,
        availableBalance: .zero,
        monthlyAmortization: .zero,
        monthlySavingsReserve: .zero,
        disposableCash: .zero
    )
}
