import CryptoKit
import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// OAuth 2.1 登入與登出(上游 ADR 0038,#334):授權碼 + PKCE,`/oauth/token` 與 `/oauth/revoke` 是 form-urlencoded、
/// 回應不是 `{success, data}` envelope。fixture 由 `scripts/record-oauth-fixtures.sh` 用測試帳號從 prod 錄下。
@Suite("OAuth 登入與登出的翻譯")
struct OAuthTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider()

    private func auth(_ browser: FakeBrowserAuthorizer) -> LiveAuthRepository {
        LiveAuthRepository(
            client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session),
            browser: browser
        )
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    private func form(_ request: URLRequest?) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = request?.httpBody.map { String(decoding: $0, as: UTF8.self) }
        return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    private let signedIn = Session(
        user: User(id: UserID("u"), email: "u@example.com", name: "U"),
        tokens: SessionTokens(access: "access", refresh: "refresh+/=&token", accessExpiresAt: nil)
    )

    @Test("登入開系統登入視窗:client_id=ios、redirect、scope full、PKCE S256、隨機 state;callback scheme 是 app 的")
    func authorizeURL() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let browser = FakeBrowserAuthorizer(.code("the-code"))

        _ = try await auth(browser).signIn(registering: false)

        let url = try #require(browser.openedURLs.first)
        #expect(url.absoluteString.hasPrefix(stub.baseURL.appending(path: "oauth/authorize").absoluteString))
        let params = query(url)
        #expect(params["client_id"] == "ios")
        #expect(params["redirect_uri"] == "com.raychiu.mymoney:/oauth/callback")
        #expect(params["response_type"] == "code")
        #expect(params["scope"] == "full")
        #expect(params["code_challenge_method"] == "S256")
        #expect(params["mode"] == nil)
        #expect((params["state"]?.count ?? 0) >= 16)
        #expect(browser.callbackSchemes == ["com.raychiu.mymoney"])
    }

    @Test("註冊開同一個登入視窗的註冊模式(mode=register)")
    func registerOpensRegisterMode() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let browser = FakeBrowserAuthorizer(.code("the-code"))

        _ = try await auth(browser).signIn(registering: true)

        #expect(query(browser.openedURLs.first)["mode"] == "register")
    }

    @Test("用授權碼換權杖:form-urlencoded,code_verifier 的 S256 等於授權網址的 code_challenge")
    func tokenExchangeRequest() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let browser = FakeBrowserAuthorizer(.code("the-code"))

        _ = try await auth(browser).signIn(registering: false)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "oauth/token"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = form(request)
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["code"] == "the-code")
        #expect(body["redirect_uri"] == "com.raychiu.mymoney:/oauth/callback")
        #expect(body["client_id"] == "ios")
        let verifier = try #require(body["code_verifier"])
        #expect(verifier.count >= 43)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(query(browser.openedURLs.first)["code_challenge"] == challenge)
    }

    @Test("token 回應(非 envelope)解成 session:使用者取自存取權杖的 payload,存取權杖 15 分鐘後到期")
    func tokenResponseDecodesSession() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let before = Date()

        let result = try await auth(FakeBrowserAuthorizer(.code("the-code"))).signIn(registering: false)

        #expect(result.user == User(
            id: UserID("ff646114-6f6b-4a37-9e27-4757868af51d"),
            email: "mymoney-ios-test@example.com",
            name: "iOS 測試帳號"
        ))
        #expect(result.tokens.access?.hasPrefix("eyJ") == true)
        #expect(result.tokens.refresh == "fake-fixture-refresh-token")
        let expiry = try #require(result.tokens.accessExpiresAt)
        #expect(expiry >= before.addingTimeInterval(900) && expiry <= Date().addingTimeInterval(900))
    }

    @Test("token 端點的錯誤 {error, error_description} 照顯示 error_description")
    func tokenErrorShowsDescription() async throws {
        try stub.reply(status: 400, fixture: "oauth-token-invalid-grant.json")

        await #expect(throws: RepositoryError.rejected("授權碼無效或已被使用")) {
            try await auth(FakeBrowserAuthorizer(.code("used-code"))).signIn(registering: false)
        }
    }

    @Test("使用者關掉登入視窗:丟 CancellationError,不送 token 請求")
    func cancelledDoesNotExchange() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")

        await #expect(throws: CancellationError.self) {
            try await auth(FakeBrowserAuthorizer(.cancelled)).signIn(registering: false)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("callback 帶 error 時照顯示 error_description,不送 token 請求")
    func callbackErrorShowsDescription() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        // 格式照上游 oauth.ts 的 redirectWithError:error、error_description、state。
        let browser = FakeBrowserAuthorizer(.callback(
            "com.raychiu.mymoney:/oauth/callback?error=invalid_scope&error_description=%E4%B8%8D%E6%94%AF%E6%8F%B4%E7%9A%84%20scope&state=x"
        ))

        await #expect(throws: RepositoryError.rejected("不支援的 scope")) {
            try await auth(browser).signIn(registering: false)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("callback 的 state 跟送出的不同時拒絕,不送 token 請求")
    func stateMismatchIsRejected() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let browser = FakeBrowserAuthorizer(.callback("com.raychiu.mymoney:/oauth/callback?code=c&state=forged"))

        await #expect(throws: RepositoryError.self) {
            try await auth(browser).signIn(registering: false)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("登出:更新權杖以 form-urlencoded 送到 POST /oauth/revoke")
    func signOutRevokes() async throws {
        try stub.reply(status: 200, fixture: "oauth-revoke.json")

        await auth(FakeBrowserAuthorizer(.cancelled)).signOut(signedIn)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "oauth/revoke"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(form(request) == ["token": "refresh+/=&token"])
    }

    @Test("登出時後端出錯也不丟錯(本機一律登出)")
    func signOutSwallowsErrors() async throws {
        try stub.reply(status: 500, fixture: "auth-login-malformed-body.txt")

        await auth(FakeBrowserAuthorizer(.cancelled)).signOut(signedIn)

        #expect(stub.requests.count == 1)
    }
}
