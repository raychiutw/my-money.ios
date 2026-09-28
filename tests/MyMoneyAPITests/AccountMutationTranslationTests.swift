import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("資金帳戶的新增、編輯、刪除(POST、PUT、DELETE /accounts)")
struct AccountMutationTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveAccountRepository {
        LiveAccountRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    @Test("新增銀行存款帳戶：只送銀行存款帳戶的欄位，不送信用額度與日期")
    func createBankSendsOnlyBankFields() async throws {
        try stub.reply(status: 201, fixture: "accounts-create-bank.json")

        try await repository.create(.bank(BankAccountDraft(
            name: "iOS 測試存款", colorHex: "#A8D8EA", balance: Money(50000), isJointFund: false
        )))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "accounts"))
        let json = try body(of: request)
        #expect(json["type"] as? String == "bank")
        #expect(json["name"] as? String == "iOS 測試存款")
        #expect(json["balance"] as? Int == 50000)
        #expect(json["unbilled"] as? Int == 0)
        #expect(json["color"] as? String == "#A8D8EA")
        #expect(json["is_joint"] as? Int == 0)
        #expect(json["credit_limit"] == nil)
        #expect(json["statement_day"] == nil)
        #expect(json["payment_due_day"] == nil)
    }

    @Test("新增信用卡帳戶：已出帳待繳金額送成 balance,另有未出帳金額、額度與日期")
    func createCreditCardSendsCardFields() async throws {
        try stub.reply(status: 201, fixture: "accounts-create-credit-card.json")

        try await repository.create(.creditCard(CreditCardDraft(
            name: "iOS 測試信用卡",
            colorHex: "#FFD4A0",
            billedDebt: Money(12000),
            unbilledDebt: Money(3500),
            creditLimit: Money(100_000),
            statementDay: 15,
            paymentDueDay: 5
        )))

        let json = try body(of: try #require(stub.requests.first))
        #expect(json["type"] as? String == "credit_card")
        #expect(json["balance"] as? Int == 12000)
        #expect(json["unbilled"] as? Int == 3500)
        #expect(json["credit_limit"] as? Int == 100_000)
        #expect(json["statement_day"] as? Int == 15)
        #expect(json["payment_due_day"] as? Int == 5)
        #expect(json["is_joint"] as? Int == 0)
    }

    /// 後端的 PUT 在沒收到 `is_joint` 時會寫成 0,所以編輯時一定要送出原本的值。
    @Test("編輯時 PUT /accounts/:id,並送出家庭共同基金的標記，避免被後端清掉")
    func updateSendsJointFundFlag() async throws {
        try stub.reply(status: 200, fixture: "accounts-update.json")

        try await repository.update(AccountID("7ed95caa-92e4-4f25-904a-e961317a1d47"), with: .bank(BankAccountDraft(
            name: "iOS 暫時帳戶(改名)", colorHex: "#C9D6FF", balance: Money(250), isJointFund: true
        )))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == stub.baseURL.appending(path: "accounts/7ed95caa-92e4-4f25-904a-e961317a1d47"))
        let json = try body(of: request)
        #expect(json["is_joint"] as? Int == 1)
        #expect(json["balance"] as? Int == 250)
    }

    @Test("刪除時 DELETE /accounts/:id,後端回 {success, data: null} 視為成功")
    func deleteSucceeds() async throws {
        try stub.reply(status: 200, fixture: "accounts-delete.json")

        try await repository.delete(AccountID("7ed95caa-92e4-4f25-904a-e961317a1d47"))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url == stub.baseURL.appending(path: "accounts/7ed95caa-92e4-4f25-904a-e961317a1d47"))
    }

    @Test("刪除不存在的資金帳戶時，原樣傳遞「帳戶不存在」")
    func deleteNotFoundPassesMessage() async throws {
        try stub.reply(status: 404, fixture: "accounts-delete-not-found.json")

        await #expect(throws: RepositoryError.rejected("帳戶不存在")) {
            try await repository.delete(AccountID("7ed95caa-92e4-4f25-904a-e961317a1d47"))
        }
    }
}
