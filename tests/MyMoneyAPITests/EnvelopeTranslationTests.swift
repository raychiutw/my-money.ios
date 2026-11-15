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

    @Test("失敗的回應沒有附訊息時，跟 web 一樣顯示「請求失敗」")
    func failureWithoutMessageShowsRequestFailed() async throws {
        // body 是真實的 `{success, message}` 回應，只把狀態碼換成 500:
        // web 的判斷是 `!res.ok || !data.success`,兩者任一成立就丟出 `data.error || '請求失敗'`。
        try stub.reply(status: 500, fixture: "bot-bindings-delete.json")

        await #expect(throws: RepositoryError.rejected("請求失敗")) {
            try await client.send("DELETE", "/bot/bindings/fixture-nonexistent-binding")
        }
    }

    @Test("401 帶 invalid_token 時是 session 過期，不看路徑(/auth/sessions 也走權杖驗證)")
    func invalidTokenOnAuthPathIsSessionExpired() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client.send("GET", "/auth/sessions")
        }
        #expect(session.expirationCount == 1)
    }

    @Test("401 帶 invalid_dpop_proof 時顯示後端訊息，不清掉 session")
    func invalidDPoPProofIsNotSessionExpired() async throws {
        // prod 要有 DPoP 權杖才錄得到;標頭照上游 c899f01 middleware/jwt.ts 的 unauthorized(…, 'DPoP', 'invalid_dpop_proof')。
        try stub.reply(
            status: 401,
            fixture: "accounts-invalid-token.json",
            headers: ["WWW-Authenticate": #"DPoP error="invalid_dpop_proof""#]
        )

        await #expect(throws: RepositoryError.rejected("Token 無效或已過期")) {
            try await client.send("GET", "/accounts")
        }
        #expect(session.expirationCount == 0)
    }

    @Test("401 沒有 WWW-Authenticate 時照顯示後端訊息，不看路徑也不清掉 session")
    func unauthorizedWithoutChallengeShowsBackendMessage() async throws {
        // 真實的帳密錯誤回應:後端的帳密錯誤、「目前密碼錯誤」都不帶 WWW-Authenticate。
        try stub.reply(status: 401, fixture: "auth-login-wrong-password.json")

        await #expect(throws: RepositoryError.invalidCredentials("Email 或密碼錯誤")) {
            try await client.send("GET", "/accounts")
        }
        #expect(session.expirationCount == 0)
    }

    @Test("每個請求的 User-Agent 都帶 MyMoney-iOS(後端用它產生裝置名稱)")
    func requestCarriesUserAgent() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")

        try await client.send("DELETE", "/bot/bindings/fixture-nonexistent-binding")

        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("MyMoney-iOS") == true)
    }

    @Test("401 帶 invalid_token(prod 錄下的標頭)時是 session 過期")
    func unauthorizedIsSessionExpired() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client.send("GET", "/accounts")
        }
    }

    @Test("401 帶 invalid_token 時通知 app 清掉 session")
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
