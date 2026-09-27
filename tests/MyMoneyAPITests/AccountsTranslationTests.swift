import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("資金帳戶的翻譯(GET /accounts、GET /accounts/balance)")
struct AccountsTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveAccountRepository {
        LiveAccountRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("GET /accounts 帶上 Bearer token")
    func listRequestsAccounts() async throws {
        try stub.reply(status: 200, fixture: "accounts-list.json")

        _ = try await repository.accounts()

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url == stub.baseURL.appending(path: "accounts"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    }

    @Test("銀行存款帳戶的 balance 解讀成餘額")
    func bankBalanceIsBalance() async throws {
        try stub.reply(status: 200, fixture: "accounts-list.json")

        let accounts = try await repository.accounts()

        #expect(accounts.first == .bank(BankAccount(
            id: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            name: "iOS 測試存款",
            colorHex: "#A8D8EA",
            balance: Money(50000),
            isJointFund: false
        )))
    }

    @Test("信用卡帳戶的 balance 解讀成已出帳待繳金額，unbilled 是未出帳金額")
    func creditCardBalanceIsBilledDebt() async throws {
        try stub.reply(status: 200, fixture: "accounts-list.json")

        let accounts = try await repository.accounts()

        #expect(accounts.count == 3)
        #expect(accounts[1] == .creditCard(CreditCard(
            id: AccountID("70b75089-3652-40a3-8c47-c23d04aab28c"),
            name: "iOS 測試信用卡",
            colorHex: "#FFD4A0",
            billedDebt: Money(12000),
            unbilledDebt: Money(3500),
            creditLimit: Money(100_000),
            statementDay: 15,
            paymentDueDay: 5
        )))
    }

    @Test("沒有任何資金帳戶時是空清單")
    func emptyList() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-empty.json")

        #expect(try await repository.accounts().isEmpty)
    }

    @Test("GET /accounts/balance 的 camelCase 欄位解讀成淨可用資產等指標")
    func balanceSummaryDecodesCamelCase() async throws {
        try stub.reply(status: 200, fixture: "accounts-balance.json")

        let summary = try await repository.balanceSummary()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts/balance"))
        #expect(summary == BalanceSummary(
            bankBalanceTotal: Money(50000),
            billedDebtTotal: Money(20000),
            unbilledDebtTotal: Money(8500),
            availableBalance: Money(21500),
            monthlyAmortization: Money(0),
            monthlySavingsReserve: Money(0),
            disposableCash: Money(21500)
        ))
    }

    @Test("token 失效時是 session 過期")
    func invalidTokenExpiresSession() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await repository.accounts()
        }
    }
}
