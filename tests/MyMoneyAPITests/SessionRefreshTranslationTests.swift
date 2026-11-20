import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 刷臉讀出受保護的 session 後先換新權杖(#365):`AuthRepository.refreshSession()` 不經一般請求，直接用更新權杖換新，
/// 沿用 `APIClient` 既有的 refresh(輪替、`invalid_grant` 登出並刪 DPoP 金鑰、網路錯誤不登出)。
@Suite("刷臉後先換新權杖")
struct SessionRefreshTranslationTests {
    private let stub = HTTPStub()

    private func auth(_ session: FakeSessionProvider, keys: InMemoryDPoPKeyStore? = nil) -> LiveAuthRepository {
        LiveAuthRepository(
            client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session, dpopKeys: keys),
            browser: FakeBrowserAuthorizer(.code("unused"))
        )
    }

    /// 存取權杖還有效:一般請求不會 refresh,這個入口照樣換新。
    private static let valid = SessionTokens(access: "old-access", refresh: "stored-refresh", accessExpiresAt: .now.addingTimeInterval(600))

    @Test("換新成功:送出 refresh_token,輪替後的權杖交給 app 那一側(存取權杖還有效也換)")
    func refreshRotatesTokens() async throws {
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: Self.valid)

        try await auth(session).refreshSession()

        let request = try #require(stub.requests(to: "/oauth/token").first)
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=stored-refresh"))
        #expect(session.tokens?.refresh == "fake-fixture-rotated-refresh-token")
        #expect(session.expirationCount == 0)
    }

    @Test("更新權杖已失效(invalid_grant):通知 app 結束 session、刪掉 DPoP 金鑰,丟 sessionExpired")
    func invalidGrantExpiresSessionAndDeletesKey() async throws {
        try stub.route("/oauth/token", [(400, "oauth-token-refresh-invalid-grant.json")])
        let session = FakeSessionProvider(tokens: Self.valid)
        let keys = InMemoryDPoPKeyStore()

        await #expect(throws: RepositoryError.sessionExpired) {
            try await auth(session, keys: keys).refreshSession()
        }
        #expect(session.expirationCount == 1)
        #expect(keys.publicKey == nil)
    }

    @Test("網路錯誤:照一般錯誤丟出,不登出、保留更新權杖")
    func networkErrorKeepsSession() async throws {
        try stub.route("/oauth/token", [nil])
        let session = FakeSessionProvider(tokens: Self.valid)

        await #expect(throws: URLError.self) {
            try await auth(session).refreshSession()
        }
        #expect(session.expirationCount == 0)
        #expect(session.tokens == Self.valid)
    }
}
