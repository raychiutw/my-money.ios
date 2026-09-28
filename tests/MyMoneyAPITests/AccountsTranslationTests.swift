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

    @Test("GET /accounts 帶上 Bearer token,並明確帶 scope=all(不依賴後端的預設範圍)")
    func listRequestsAccounts() async throws {
        try stub.reply(status: 200, fixture: "accounts-list.json")

        _ = try await repository.accounts()

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url == stub.baseURL.appending(path: "accounts").appending(queryItems: [
            URLQueryItem(name: "scope", value: "all"),
        ]))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    }

    @Test("帳戶檢視範圍：家庭公用帶 scope=household,只回傳家庭公用的帳戶")
    func householdScopeListsJointAccounts() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-household.json")

        let accounts = try await repository.accounts(scope: .household)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts").appending(queryItems: [
            URLQueryItem(name: "scope", value: "household"),
        ]))
        #expect(accounts.map(\.name) == ["iOS 家庭共同基金"])
    }

    @Test("帳戶檢視範圍：個人私帳的餘額摘要帶 scope=personal,不含家庭公用帳戶")
    func personalScopeBalanceSummary() async throws {
        try stub.reply(status: 200, fixture: "accounts-balance-personal.json")

        let summary = try await repository.balanceSummary(scope: .personal)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts/balance").appending(queryItems: [
            URLQueryItem(name: "scope", value: "personal"),
        ]))
        #expect(summary.bankBalanceTotal == Money(94700))
        #expect(summary.availableBalance == Money(66820))
    }

    @Test("現金錢包的 balance 解讀成餘額")
    func cashWalletBalanceIsBalance() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-with-cash.json")

        let accounts = try await repository.accounts()

        try #require(accounts.count == 5)
        #expect(accounts[4] == .cash(CashWallet(
            id: AccountID("0fa1efa6-9789-4040-9fe7-22ef3be11b3c"),
            name: "iOS 測試皮夾",
            colorHex: "#10B981",
            balance: Money(1500),
            isJointFund: false
        )))
    }

    @Test("後端將來新增、iOS 還不認得的帳戶類型只略過那一個帳戶，其餘照常顯示")
    func unknownAccountTypeIsSkipped() async throws {
        let recorded = try String(decoding: Fixture.data("accounts-list-with-cash.json"), as: UTF8.self)
        let future = recorded.replacingOccurrences(of: #""type":"cash""#, with: #""type":"crypto""#)
        try #require(future != recorded)
        stub.reply(status: 200, json: Data(future.utf8))

        let accounts = try await repository.accounts()

        #expect(accounts.map(\.name) == ["iOS 測試存款", "iOS 測試信用卡", "iOS 測試小額卡", "iOS 家庭共同基金"])
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
            paymentDueDay: 5,
            sharedDebt: .zero,
            personalDebt: Money(15500)
        )))
    }

    @Test("欠款公私拆解與家庭共同基金的標記")
    func debtSplitAndJointFund() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-with-debt-split.json")

        let accounts = try await repository.accounts()

        try #require(accounts.count == 4)
        guard case .creditCard(let card) = accounts[1], case .bank(let joint) = accounts[3] else {
            Issue.record("資金帳戶的類型不對")
            return
        }
        #expect(card.sharedDebt == Money(3000))
        #expect(card.personalDebt == Money(16380))
        #expect(joint.name == "iOS 家庭共同基金")
        #expect(joint.isJointFund)
    }

    @Test("信用卡還款沖銷:POST /accounts/pay-credit-card")
    func payCreditCard() async throws {
        try stub.reply(status: 200, fixture: "accounts-pay-credit-card.json")

        try await repository.payCreditCard(CardPayment(
            bankAccountID: AccountID("c70d655c-0238-4bd7-ba83-92e165437e87"),
            creditCardID: AccountID("70b75089-3652-40a3-8c47-c23d04aab28c"),
            amount: Money(3000),
            date: CalendarDay(year: 2026, month: 9, day: 28),
            note: "繳納【iOS 測試信用卡】卡費",
            isShared: true
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/accounts/pay-credit-card")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["bank_account_id"] as? String == "c70d655c-0238-4bd7-ba83-92e165437e87")
        #expect(json["credit_card_id"] as? String == "70b75089-3652-40a3-8c47-c23d04aab28c")
        #expect(json["amount"] as? Int == 3000)
        #expect(json["date"] as? String == "2026-09-28")
        #expect(json["note"] as? String == "繳納【iOS 測試信用卡】卡費")
        #expect(json["is_shared"] as? Int == 1)
    }

    @Test("信用卡還款沖銷的錯誤原樣傳遞", arguments: [
        ("accounts-pay-credit-card-over.json", "繳款金額不可超過當前待繳總額 NT$ 16,380"),
        ("accounts-pay-credit-card-missing.json", "請填寫扣款帳戶、信用卡及正確繳費金額"),
    ])
    func payRejected(fixture: String, message: String) async throws {
        try stub.reply(status: 400, fixture: fixture)

        await #expect(throws: RepositoryError.rejected(message)) {
            try await repository.payCreditCard(CardPayment(
                bankAccountID: AccountID("bank"), creditCardID: AccountID("card"), amount: Money(1),
                date: CalendarDay(year: 2026, month: 9, day: 28), note: "", isShared: false
            ))
        }
        // 個人私帳送成 is_shared: 0。
        let body = try #require(stub.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["is_shared"] as? Int == 0)
    }

    @Test("結帳日出帳結轉：回傳後端的訊息;沒有未出帳金額時原樣傳遞錯誤")
    func rollOverStatement() async throws {
        let card = AccountID("70b75089-3652-40a3-8c47-c23d04aab28c")

        try stub.reply(status: 200, fixture: "accounts-rollover-statement.json")
        let message = try await repository.rollOverStatement(card)
        #expect(message == "已將未出帳 NT$ 7,380 成功結轉為已出帳待繳！")
        #expect(stub.requests.last?.httpMethod == "POST")
        #expect(stub.requests.last?.url?.path() == "/accounts/70b75089-3652-40a3-8c47-c23d04aab28c/rollover-statement")

        try stub.reply(status: 400, fixture: "accounts-rollover-statement-none.json")
        await #expect(throws: RepositoryError.rejected("目前無未出帳金額需結轉")) {
            try await repository.rollOverStatement(card)
        }
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

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts/balance").appending(queryItems: [
            URLQueryItem(name: "scope", value: "all"),
        ]))
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

    @Test("GET /accounts/balance 的 cashTotal 是現金錢包總額，淨可用餘額由後端算好(含現金)")
    func balanceSummaryIncludesCashTotal() async throws {
        try stub.reply(status: 200, fixture: "accounts-balance-with-cash.json")

        let summary = try await repository.balanceSummary()

        #expect(summary.cashTotal == Money(1500))
        #expect(summary.bankBalanceTotal == Money(101_700))
        #expect(summary.availableBalance == Money(73820))
    }

    @Test("token 失效時是 session 過期")
    func invalidTokenExpiresSession() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await repository.accounts()
        }
    }
}
