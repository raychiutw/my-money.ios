import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 更新權杖輪替與自動續期(#335):存取權杖到期前、冷啟動沒有存取權杖、或收到 `invalid_token` 時,用更新權杖換新。
/// fixture 由 `scripts/record-oauth-fixtures.sh` 用測試帳號從 prod 錄下。
@Suite("更新權杖輪替與自動續期")
struct TokenRefreshTranslationTests {
    private let stub = HTTPStub()
    private static let protectedPath = "/bot/bindings/fixture-nonexistent-binding"

    private func client(_ session: FakeSessionProvider) -> APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session)
    }

    private func form(_ request: URLRequest?) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = request?.httpBody.map { String(decoding: $0, as: UTF8.self) }
        return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    /// 冷啟動從裝置讀回的登入工作階段:只有更新權杖。
    private static let restored = SessionTokens(access: nil, refresh: "stored-refresh", accessExpiresAt: nil)
    /// 還有效的存取權杖。
    private static let valid = SessionTokens(access: "old-access", refresh: "stored-refresh", accessExpiresAt: .now.addingTimeInterval(600))

    @Test("冷啟動沒有存取權杖:先 refresh(form-urlencoded、client_id=ios),再用新的存取權杖送原請求")
    func coldStartRefreshesFirst() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: Self.restored)

        try await client(session).send("DELETE", Self.protectedPath)

        let refresh = try #require(stub.requests(to: "/oauth/token").first)
        #expect(refresh.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(form(refresh) == ["grant_type": "refresh_token", "refresh_token": "stored-refresh", "client_id": "ios"])
        let access = try #require(session.tokens?.access)
        #expect(access.hasPrefix("eyJ"))
        let original = try #require(stub.requests(to: Self.protectedPath).first)
        #expect(original.value(forHTTPHeaderField: "Authorization") == "Bearer \(access)")
    }

    @Test("refresh 成功後改存輪替後的新更新權杖,存取權杖 15 分鐘後到期")
    func refreshStoresRotatedToken() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: Self.restored)
        let before = Date()

        try await client(session).send("DELETE", Self.protectedPath)

        let tokens = try #require(session.tokens)
        #expect(tokens.refresh == "fake-fixture-rotated-refresh-token")
        let expiry = try #require(tokens.accessExpiresAt)
        #expect(expiry >= before.addingTimeInterval(900) && expiry <= Date().addingTimeInterval(900))
    }

    @Test("存取權杖快到期(一分鐘內)時先 refresh 再送")
    func expiringAccessTokenRefreshesFirst() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: SessionTokens(
            access: "old-access", refresh: "stored-refresh", accessExpiresAt: .now.addingTimeInterval(30)
        ))

        try await client(session).send("DELETE", Self.protectedPath)

        #expect(stub.requests(to: "/oauth/token").count == 1)
        #expect(stub.requests(to: Self.protectedPath).first?.value(forHTTPHeaderField: "Authorization") != "Bearer old-access")
    }

    @Test("存取權杖還有效時不 refresh")
    func validAccessTokenDoesNotRefresh() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        let session = FakeSessionProvider(tokens: Self.valid)

        try await client(session).send("DELETE", Self.protectedPath)

        #expect(stub.requests(to: "/oauth/token").isEmpty)
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    }

    @Test("同時多個請求只送一個 refresh,其他請求等它的結果再用新的存取權杖送出")
    func concurrentRequestsShareOneRefresh() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        // 回應延遲,讓三個請求真的在 refresh 進行中時抵達。
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")], delay: 0.3)
        let session = FakeSessionProvider(tokens: Self.restored)
        let api = client(session)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { try await api.send("DELETE", Self.protectedPath) }
            }
            try await group.waitForAll()
        }

        #expect(stub.requests(to: "/oauth/token").count == 1)
        let access = try #require(session.tokens?.access)
        let sent = stub.requests(to: Self.protectedPath).map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(sent == Array(repeating: "Bearer \(access)", count: 3))
    }

    @Test("401 invalid_token:refresh 後用新的存取權杖重送原請求一次,不登出")
    func invalidTokenRefreshesAndRetries() async throws {
        try stub.route(Self.protectedPath, [(401, "accounts-invalid-token.json"), (200, "bot-bindings-delete.json")])
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: Self.valid)

        try await client(session).send("DELETE", Self.protectedPath)

        let sent = stub.requests(to: Self.protectedPath).map { $0.value(forHTTPHeaderField: "Authorization") }
        let access = try #require(session.tokens?.access)
        #expect(sent == ["Bearer old-access", "Bearer \(access)"])
        #expect(session.expirationCount == 0)
    }

    @Test("refresh 後重送仍 401 invalid_token 才登出,不再 refresh 第二次")
    func retryStillUnauthorizedSignsOut() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: Self.valid)

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client(session).send("DELETE", Self.protectedPath)
        }
        #expect(stub.requests(to: Self.protectedPath).count == 2)
        #expect(stub.requests(to: "/oauth/token").count == 1)
        #expect(session.expirationCount == 1)
    }

    @Test("refresh 回 invalid_grant:清掉登入狀態回登入頁,原請求不送")
    func invalidGrantSignsOut() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(400, "oauth-token-refresh-invalid-grant.json")])
        let session = FakeSessionProvider(tokens: Self.restored)

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client(session).send("DELETE", Self.protectedPath)
        }
        #expect(session.expirationCount == 1)
        #expect(stub.requests(to: Self.protectedPath).isEmpty)
    }

    @Test("refresh 網路錯誤:不登出,保留更新權杖,原請求照一般錯誤處理(上游 #208)")
    func networkErrorDoesNotSignOut() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [nil])
        let session = FakeSessionProvider(tokens: Self.restored)

        await #expect(throws: URLError.self) {
            try await client(session).send("DELETE", Self.protectedPath)
        }
        #expect(session.expirationCount == 0)
        #expect(session.tokens == Self.restored)
    }

    @Test("401 invalid_token 後 refresh 遇到網路錯誤:不登出,原請求照一般錯誤處理")
    func networkErrorAfterInvalidTokenDoesNotSignOut() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")
        try stub.route("/oauth/token", [nil])
        let session = FakeSessionProvider(tokens: Self.valid)

        await #expect(throws: URLError.self) {
            try await client(session).send("DELETE", Self.protectedPath)
        }
        #expect(session.expirationCount == 0)
        #expect(session.tokens == Self.valid)
    }

    @Test("refresh 回 5xx:不登出,保留更新權杖")
    func serverErrorDoesNotSignOut() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(500, "auth-login-malformed-body.txt")])
        let session = FakeSessionProvider(tokens: Self.restored)

        await #expect(throws: RepositoryError.unreadableResponse) {
            try await client(session).send("DELETE", Self.protectedPath)
        }
        #expect(session.expirationCount == 0)
        #expect(session.tokens == Self.restored)
    }
}
