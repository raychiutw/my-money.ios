import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("機器人記帳的翻譯(/bot)")
struct BotTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveBotRepository {
        LiveBotRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("產生綁定驗證碼:POST /bot/pairing-code,帶上有效秒數")
    func pairingCode() async throws {
        try stub.reply(status: 200, fixture: "bot-pairing-code.json")

        let code = try await repository.pairingCode()

        #expect(stub.requests.first?.httpMethod == "POST")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "bot/pairing-code"))
        #expect(code == PairingCode(code: "XX2S3H", expiresInSeconds: 600))
    }

    @Test("已綁定的帳號：平台與名稱")
    func bindings() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings.json")

        let bindings = try await repository.bindings()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "bot/bindings"))
        #expect(bindings == [BotBinding(
            id: BotBindingID("3f74d442-93a5-4076-b4f6-292e70367166"), platform: .line, displayName: "模擬測試助手"
        )])
    }

    @Test("還沒有綁定任何帳號")
    func noBindings() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-empty.json")

        #expect(try await repository.bindings().isEmpty)
    }

    @Test("解除綁定:DELETE 只回 {success, message}")
    func unbind() async throws {
        try stub.reply(status: 200, fixture: "bot-unbind.json")

        try await repository.unbind(BotBindingID("3f74d442-93a5-4076-b4f6-292e70367166"))

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "bot/bindings/3f74d442-93a5-4076-b4f6-292e70367166"))
    }

    @Test("模擬對話:POST /bot/test-simulate {text, platform: line},回傳機器人的回覆")
    func simulate() async throws {
        try stub.reply(status: 200, fixture: "bot-simulate-expense.json")

        let reply = try await repository.simulate("午餐 120")

        let request = try #require(stub.requests.first)
        #expect(request.url == stub.baseURL.appending(path: "bot/test-simulate"))
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["text"] as? String == "午餐 120")
        #expect(json["platform"] as? String == "line")
        #expect(reply.hasPrefix("📝 記帳成功！"))
        #expect(reply.contains("金額：NT$ 120"))
    }

    @Test("查帳的回覆")
    func query() async throws {
        try stub.reply(status: 200, fixture: "bot-simulate-query.json")

        #expect(try await repository.simulate("查帳").hasPrefix("📊 即時財務總覽"))
    }

    @Test("沒有訊息時原樣傳遞「請輸入測試訊息」")
    func missingText() async throws {
        try stub.reply(status: 400, fixture: "bot-simulate-missing-text.json")

        await #expect(throws: RepositoryError.rejected("請輸入測試訊息")) {
            try await repository.simulate("")
        }
    }
}
