import MyMoneyDomain

/// 不連網路的資金帳戶:資料由測試決定，也可以指定失敗。
public actor InMemoryAccountRepository: AccountRepository {
    private var storedAccounts: [Account]
    private var summary: BalanceSummary
    private var failure: RepositoryError?
    private let gate: Gate?

    public init(accounts: [Account], summary: BalanceSummary, gate: Gate? = nil) {
        storedAccounts = accounts
        self.summary = summary
        self.gate = gate
    }

    public func accounts() async throws -> [Account] {
        await gate?.pass()
        if let failure { throw failure }
        return storedAccounts
    }

    public func balanceSummary() async throws -> BalanceSummary {
        await gate?.pass()
        if let failure { throw failure }
        return summary
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 換成新的資料(模擬家人在別的裝置上改了資料)。
    public func replace(accounts: [Account], summary: BalanceSummary) {
        storedAccounts = accounts
        self.summary = summary
    }
}

extension InMemoryAccountRepository {
    /// 對應 `accounts-list.json` 與 `accounts-balance.json` 的測試資料:一個銀行存款帳戶、兩張信用卡帳戶。
    public static func sample(gate: Gate? = nil) -> InMemoryAccountRepository {
        InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary, gate: gate)
    }
}

/// 畫面 model 測試與 UI 測試共用的資金帳戶。
public enum SampleAccounts {
    public static let savings = BankAccount(
        id: AccountID("sample-bank"),
        name: "iOS 測試存款",
        colorHex: "#A8D8EA",
        balance: Money(50000),
        isJointFund: false
    )

    public static let card = CreditCard(
        id: AccountID("sample-card"),
        name: "iOS 測試信用卡",
        colorHex: "#FFD4A0",
        billedDebt: Money(12000),
        unbilledDebt: Money(3500),
        creditLimit: Money(100_000),
        statementDay: 15,
        paymentDueDay: 5
    )

    /// 剩餘額度 7,000,低於 10,000 的警示門檻。
    public static let lowLimitCard = CreditCard(
        id: AccountID("sample-low-limit-card"),
        name: "iOS 測試小額卡",
        colorHex: "#F38181",
        billedDebt: Money(8000),
        unbilledDebt: Money(5000),
        creditLimit: Money(20000),
        statementDay: 1,
        paymentDueDay: 20
    )

    public static let all: [Account] = [.bank(savings), .creditCard(card), .creditCard(lowLimitCard)]

    public static let summary = BalanceSummary(
        bankBalanceTotal: Money(50000),
        billedDebtTotal: Money(20000),
        unbilledDebtTotal: Money(8500),
        availableBalance: Money(21500),
        monthlyAmortization: .zero,
        monthlySavingsReserve: .zero,
        disposableCash: Money(21500)
    )
}
