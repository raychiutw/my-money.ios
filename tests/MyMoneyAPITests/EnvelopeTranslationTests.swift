import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 三種 envelope(`{success, data}`、`{success: false, error}`、`{success, message}`)與錯誤映射。
@Suite("envelope 與錯誤映射")
struct EnvelopeTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "current-session-token")

    private var client: APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session)
    }

    @Test("無法解析的回應當成伺服器無回應")
    func unreadableResponse() async throws {
        try stub.reply(status: 500, fixture: "auth-login-malformed-body.txt")

        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveAuthRepository(client: client).login(email: "mymoney-ios-test@example.com", password: "irrelevant")
        }
    }

    @Test("只有 message、沒有 data 的 envelope 視為成功")
    func messageOnlyEnvelopeSucceeds() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")

        try await client.send("DELETE", "/bot/bindings/fixture-nonexistent-binding")
    }

    @Test("非 /auth/* 的請求回應 401 時是 session 過期")
    func unauthorizedIsSessionExpired() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client.send("GET", "/accounts")
        }
    }

    @Test("非 /auth/* 的請求回應 401 時通知 app 清掉 session")
    func unauthorizedNotifiesApp() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        _ = try? await client.send("GET", "/accounts")

        #expect(session.expirationCount == 1)
    }

    @Test("請求帶上目前 session 的 Bearer token")
    func requestCarriesBearerToken() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")

        try await client.send("DELETE", "/bot/bindings/fixture-nonexistent-binding")

        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer current-session-token")
    }

    @Test("未登入時不帶 Authorization")
    func signedOutRequestHasNoAuthorization() async throws {
        try stub.reply(status: 200, fixture: "auth-login-success.json")
        let signedOut = APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: FakeSessionProvider(token: nil))

        _ = try await LiveAuthRepository(client: signedOut).login(email: "mymoney-ios-test@example.com", password: "irrelevant")

        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
