import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("資產帳戶的翻譯(GET /accounts、GET /accounts/balance)")
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

    @Test("帳戶檢視範圍：家庭共同基金帶 scope=household,只回傳歸屬家庭共同基金的帳戶")
    func householdScopeListsJointAccounts() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-household.json")

        let accounts = try await repository.accounts(scope: .household)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts").appending(queryItems: [
            URLQueryItem(name: "scope", value: "household"),
        ]))
        #expect(accounts.map(\.name) == ["iOS 家庭共同基金"])
    }

    @Test("後端的 user_id 解讀成擁有者:現金、活存帳戶、信用卡都有(上游 ADR 0013 的編輯權限判斷，#133)")
    func ownerIDIsUserID() async throws {
        // 2026-10-02 從 prod 錄的真實回應:`user_id` 是帳戶擁有者，`is_joint` 區分個人私帳與家庭共同帳戶。
        try stub.reply(status: 200, fixture: "accounts-list-permission.json")

        let accounts = try await repository.accounts()

        let owner = UserID("ff646114-6f6b-4a37-9e27-4757868af51d")
        try #require(accounts.count == 5)
        #expect(accounts.map(\.kind) == [.bank, .creditCard, .creditCard, .bank, .cash])
        #expect(accounts.allSatisfy { $0.ownerID == owner }, "每一種帳戶都要帶擁有者")
        #expect(accounts.map(\.isJointFund) == [false, false, false, true, false])
    }

    @Test("公帳範圍會多回自己有家庭代墊欠款的個人信用卡(上游 ADR 0015):解成一般信用卡，沒有脫敏")
    func householdScopeIncludesOwnPrivateCardWithSharedDebt() async throws {
        // 2026-10-03 從 prod 錄的真實回應:在測試帳號的個人信用卡記一筆公帳支出 777 之後的 `GET /accounts?scope=household`。
        try stub.reply(status: 200, fixture: "accounts-list-household-card-advance.json")

        let accounts = try await repository.accounts(scope: .household)

        try #require(accounts.count == 2)
        guard case .creditCard(let card) = accounts[0] else {
            Issue.record("第一個不是信用卡")
            return
        }
        #expect(card.name == "iOS 測試信用卡")
        #expect(!card.isJointFund)
        #expect(!card.isMasked, "自己的卡不脫敏(沒有 is_masked)")
        #expect(card.ownerName == "iOS 測試帳號")
        #expect(card.ownerID == UserID("ff646114-6f6b-4a37-9e27-4757868af51d"))
        #expect(card.billedDebt == Money(16380))
        #expect(card.unbilledDebt == Money(777))
        #expect(card.sharedDebt == Money(777))
        #expect(card.personalDebt == Money(16380))
        #expect(accounts[1].name == "iOS 家庭共同基金")
    }

    @Test("他人的個人信用卡在公帳範圍是脫敏的:is_masked 解成脫敏，額度空白、已出帳 0、未出帳款等於家庭代墊、個人消費 0")
    func maskedCardIsDecoded() async throws {
        // 測試帳號只有自己一人，錄不到真正的脫敏回應(需要第二個帳號):把上面真實 fixture 的信用卡改成後端 ADR 0015 描述的脫敏樣子。
        // 這是手改的案例，欄位名稱與型別都沿用真實回應。
        let recorded = try Fixture.data("accounts-list-household-card-advance.json")
        var envelope = try #require(try JSONSerialization.jsonObject(with: recorded) as? [String: Any])
        var rows = try #require(envelope["data"] as? [[String: Any]])
        rows[0]["user_id"] = "sample-mei"
        rows[0]["owner_name"] = "小美"
        rows[0]["credit_limit"] = NSNull()
        rows[0]["balance"] = 0
        rows[0]["unbilled"] = 777
        rows[0]["personal_debt"] = 0
        rows[0]["is_masked"] = true
        envelope["data"] = rows
        stub.reply(status: 200, json: try JSONSerialization.data(withJSONObject: envelope))

        let accounts = try await repository.accounts(scope: .household)

        guard case .creditCard(let card) = accounts[0] else {
            Issue.record("第一個不是信用卡")
            return
        }
        #expect(card.isMasked)
        #expect(card.ownerID == UserID("sample-mei"))
        #expect(card.ownerName == "小美")
        #expect(card.creditLimit == nil)
        #expect(card.billedDebt == .zero)
        #expect(card.unbilledDebt == Money(777))
        #expect(card.sharedDebt == Money(777))
        #expect(card.personalDebt == .zero)
        #expect(card.totalDue == Money(777), "待繳總額就是家庭代墊待繳額")
    }

    @Test("is_masked 的型別還沒在 prod 看過(需要第二個帳號):true／false 與 0／1 都接受，不讓整份清單解碼失敗")
    func maskedFlagAcceptsBooleanOrNumber() async throws {
        let recorded = try Fixture.data("accounts-list-household-card-advance.json")
        for (flag, expected) in [(true as Any, true), (1, true), (0, false), (false, false)] {
            var envelope = try #require(try JSONSerialization.jsonObject(with: recorded) as? [String: Any])
            var rows = try #require(envelope["data"] as? [[String: Any]])
            rows[0]["is_masked"] = flag
            envelope["data"] = rows
            stub.reply(status: 200, json: try JSONSerialization.data(withJSONObject: envelope))

            let accounts = try await repository.accounts(scope: .household)

            guard case .creditCard(let card) = accounts[0] else {
                Issue.record("第一個不是信用卡")
                return
            }
            #expect(card.isMasked == expected, "is_masked = \(flag)")
        }
    }

    @Test("公帳範圍的餘額摘要把私卡的家庭代墊算進信用卡待繳與淨可用餘額(後端算好，iOS 照用)")
    func householdBalanceIncludesPrivateCardAdvance() async throws {
        try stub.reply(status: 200, fixture: "accounts-balance-household-card-advance.json")

        let summary = try await repository.balanceSummary(scope: .household)

        #expect(summary.bankBalanceTotal == Money(6900))
        #expect(summary.unbilledDebtTotal == Money(777))
        #expect(summary.availableBalance == Money(6123))
    }

    @Test("帳戶檢視範圍：個人私帳的餘額摘要帶 scope=personal,不含歸屬家庭共同基金的帳戶")
    func personalScopeBalanceSummary() async throws {
        try stub.reply(status: 200, fixture: "accounts-balance-personal.json")

        let summary = try await repository.balanceSummary(scope: .personal)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "accounts/balance").appending(queryItems: [
            URLQueryItem(name: "scope", value: "personal"),
        ]))
        #expect(summary.bankBalanceTotal == Money(94700))
        #expect(summary.availableBalance == Money(66820))
    }

    @Test("現金的 balance 解讀成餘額")
    func cashWalletBalanceIsBalance() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-with-cash.json")

        let accounts = try await repository.accounts()

        try #require(accounts.count == 5)
        #expect(accounts[4] == .cash(CashWallet(
            id: AccountID("0fa1efa6-9789-4040-9fe7-22ef3be11b3c"),
            name: "iOS 測試皮夾",
            colorHex: "#10B981",
            balance: Money(1500),
            isJointFund: false,
            ownerID: UserID("ff646114-6f6b-4a37-9e27-4757868af51d")
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

    @Test("活存帳戶的 balance 解讀成餘額")
    func bankBalanceIsBalance() async throws {
        try stub.reply(status: 200, fixture: "accounts-list.json")

        let accounts = try await repository.accounts()

        #expect(accounts.first == .bank(BankAccount(
            id: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            name: "iOS 測試存款",
            colorHex: "#A8D8EA",
            balance: Money(50000),
            isJointFund: false,
            ownerID: UserID("ff646114-6f6b-4a37-9e27-4757868af51d")
        )))
    }

    @Test("信用卡帳戶的 balance 解讀成已出帳待繳款，unbilled 是未出帳款")
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
            personalDebt: Money(15500),
            ownerID: UserID("ff646114-6f6b-4a37-9e27-4757868af51d"),
            ownerName: "iOS 測試帳號"
        )))
    }

    @Test("欠款公私拆解與家庭共同基金的標記")
    func debtSplitAndJointFund() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-with-debt-split.json")

        let accounts = try await repository.accounts()

        try #require(accounts.count == 4)
        guard case .creditCard(let card) = accounts[1], case .bank(let joint) = accounts[3] else {
            Issue.record("資產帳戶的類型不對")
            return
        }
        #expect(card.sharedDebt == Money(3000))
        #expect(card.personalDebt == Money(16380))
        #expect(joint.name == "iOS 家庭共同基金")
        #expect(joint.isJointFund)
    }

    @Test("信用卡扣款還款:POST /accounts/pay-credit-card")
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

    @Test("信用卡扣款還款的錯誤原樣傳遞", arguments: [
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

    @Test("ATM 提款：POST /accounts/transfer 送轉出、轉入、金額、台灣日期與備註，回傳後端的訊息")
    func transferSendsBodyAndReturnsMessage() async throws {
        try stub.reply(status: 200, fixture: "accounts-transfer-atm.json")

        let message = try await repository.transfer(AccountTransfer(
            fromAccountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            toAccountID: AccountID("0fa1efa6-9789-4040-9fe7-22ef3be11b3c"),
            amount: Money(500),
            date: CalendarDay(year: 2026, month: 9, day: 28),
            note: "ATM 提款"
        ))

        #expect(message == "ATM 提款成功 NT$ 500 (iOS 測試存款 ➡️ iOS 測試皮夾)")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "accounts/transfer"))
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["from_account_id"] as? String == "f4d3074a-4df6-4c98-bd90-bc6f2af91a37")
        #expect(json["to_account_id"] as? String == "0fa1efa6-9789-4040-9fe7-22ef3be11b3c")
        #expect(json["amount"] as? Int == 500)
        #expect(json["date"] as? String == "2026-09-28")
        #expect(json["note"] as? String == "ATM 提款")
    }

    @Test("轉帳的錯誤原樣傳遞", arguments: [
        ("accounts-transfer-same-account.json", "轉出與轉入帳戶不能相同"),
        ("accounts-transfer-insufficient.json", "轉出帳戶餘額不足（目前餘額：NT$ 2,000）"),
    ])
    func transferRejected(fixture: String, message: String) async throws {
        try stub.reply(status: 400, fixture: fixture)

        await #expect(throws: RepositoryError.rejected(message)) {
            try await repository.transfer(AccountTransfer(
                fromAccountID: AccountID("a"), toAccountID: AccountID("b"), amount: Money(1),
                date: CalendarDay(year: 2026, month: 9, day: 28), note: ""
            ))
        }
    }

    @Test("結帳日出帳作業：回傳後端的訊息;沒有未出帳款時原樣傳遞錯誤")
    func rollOverStatement() async throws {
        // 出帳作業有未出帳款才能做，所以用「iOS 測試小額卡」(未出帳 5000)錄的;訊息是後端 `97f4789` 的原文，iOS 原樣傳遞，不依文字判斷。
        let card = AccountID("a1d2f913-9872-4868-88de-0e523ca46a3c")

        try stub.reply(status: 200, fixture: "accounts-rollover-statement.json")
        let message = try await repository.rollOverStatement(card)
        #expect(message == "帳單出帳作業完成！已轉入已出帳待繳款。")
        #expect(stub.requests.last?.httpMethod == "POST")
        #expect(stub.requests.last?.url?.path() == "/accounts/a1d2f913-9872-4868-88de-0e523ca46a3c/rollover-statement")

        try stub.reply(status: 400, fixture: "accounts-rollover-statement-none.json")
        await #expect(throws: RepositoryError.rejected("目前無未出帳金額需出帳")) {
            try await repository.rollOverStatement(card)
        }
    }

    @Test("校準未出帳:POST /accounts/:id/reconcile 沒有 body,回傳後端的訊息;不是信用卡時傳遞後端的錯誤")
    func reconcileUnbilled() async throws {
        try stub.reply(status: 200, fixture: "accounts-reconcile.json")
        let message = try await repository.reconcileUnbilled(AccountID("70b75089-3652-40a3-8c47-c23d04aab28c"))
        #expect(message == "已自動校準「iOS 測試信用卡」未出帳金額為 NT$ 0")
        #expect(stub.requests.last?.httpMethod == "POST")
        #expect(stub.requests.last?.url?.path() == "/accounts/70b75089-3652-40a3-8c47-c23d04aab28c/reconcile")
        #expect(stub.requests.last?.httpBody == nil)

        try stub.reply(status: 404, fixture: "accounts-reconcile-not-card.json")
        await #expect(throws: RepositoryError.rejected("信用卡不存在或無權限")) {
            try await repository.reconcileUnbilled(AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"))
        }
    }

    @Test("沒有任何資產帳戶時是空清單")
    func emptyList() async throws {
        try stub.reply(status: 200, fixture: "accounts-list-empty.json")

        #expect(try await repository.accounts().isEmpty)
    }

    @Test("GET /accounts/balance 的 camelCase 欄位解讀成淨可用餘額等指標")
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

    @Test("GET /accounts/balance 的 cashTotal 是現金總額，淨可用餘額由後端算好(含現金)")
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
