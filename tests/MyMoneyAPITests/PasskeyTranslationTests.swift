import CryptoKit
import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// Passkey 登入與管理(#339)。登入走 WebAuthn 授權橋接:`/auth/passkey/login/options` → 原生 assertion →
/// `POST /oauth/passkey/authorize`(PKCE)→ 授權碼 → `/oauth/token`。WebAuthn 的二進位欄位一律 base64url。
/// 成功的 `/oauth/passkey/authorize`、`/auth/passkey/register/verify`、非空清單、改名與刪除是手寫的(測試帳號沒有 passkey,
/// 要真機才建得出來),見 Fixtures/README.md「Passkey(#339)」。
@Suite("Passkey 的翻譯")
struct PasskeyTranslationTests {
    private let stub = HTTPStub()

    private func client(token: String? = nil) -> APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: FakeSessionProvider(token: token))
    }

    private func auth(
        _ authenticator: FakePasskeyAuthenticator, browser: FakeBrowserAuthorizer = FakeBrowserAuthorizer(.cancelled)
    ) -> LiveAuthRepository {
        LiveAuthRepository(client: client(), browser: browser, passkeys: authenticator)
    }

    private func repository(_ authenticator: FakePasskeyAuthenticator = FakePasskeyAuthenticator()) -> LivePasskeyRepository {
        LivePasskeyRepository(client: client(token: "fixture-token"), authenticator: authenticator)
    }

    private func json(_ request: URLRequest?) throws -> [String: Any] {
        let body = try #require(request?.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func form(_ request: URLRequest?) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = request?.httpBody.map { String(decoding: $0, as: UTF8.self) }
        return Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    private func routePasskeySignIn() throws {
        try stub.route("/auth/passkey/login/options", [(200, "passkey-login-options.json")])
        try stub.route("/oauth/passkey/authorize", [(200, "oauth-passkey-authorize.json")])
        try stub.route("/oauth/token", [(200, "oauth-token-authorization-code.json")])
    }

    /// `passkey-login-options.json` 的 challenge(標準 base64)。
    private let loginChallenge = Data(base64Encoded: "7xIYiecbMmN2yMnVZzdqGV+ZJtSSuQnrq0ywdCA/R/8=")!

    @Test("登入頁要求 passkey(passkey_requested、state 相符):改走原生 passkey 登入並換到 session")
    func passkeyRequestedSwitchesToPasskey() async throws {
        try routePasskeySignIn()
        let authenticator = FakePasskeyAuthenticator()

        let session = try await auth(authenticator, browser: FakeBrowserAuthorizer(.passkeyRequested)).signIn(registering: false)

        #expect(authenticator.assertions.count == 1)
        #expect(session.user.email == "mymoney-ios-test@example.com")
    }

    @Test("passkey_requested 之後使用者取消 passkey:丟 CancellationError(留在登入頁,不算錯誤)")
    func passkeyRequestedThenCancelled() async throws {
        try routePasskeySignIn()

        await #expect(throws: CancellationError.self) {
            try await auth(FakePasskeyAuthenticator(cancels: true), browser: FakeBrowserAuthorizer(.passkeyRequested))
                .signIn(registering: false)
        }
    }

    @Test("passkey_requested 的 state 跟送出的不同:照 state 不符拒絕,不叫 passkey")
    func passkeyRequestedWithForgedStateIsRejected() async throws {
        try routePasskeySignIn()
        let authenticator = FakePasskeyAuthenticator()
        let browser = FakeBrowserAuthorizer(.callback(
            "com.raychiu.mymoney:/oauth/callback?error=passkey_requested&error_description=x&state=forged"
        ))

        await #expect(throws: RepositoryError.rejected("登入失敗，請再試一次")) {
            try await auth(authenticator, browser: browser).signIn(registering: false)
        }
        #expect(authenticator.assertions.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test("passkey 登入:用登入 options 的 RP ID 與 challenge 向驗證器要 assertion")
    func signInAsksAuthenticator() async throws {
        try routePasskeySignIn()
        let authenticator = FakePasskeyAuthenticator()

        _ = try await auth(authenticator).signInWithPasskey()

        let options = try #require(stub.requests(to: "/auth/passkey/login/options").first)
        #expect(options.httpMethod == "POST")
        #expect(options.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(authenticator.assertions == [.init(relyingPartyID: "my-money-onion.pages.dev", challenge: loginChallenge)])
    }

    @Test("passkey 登入:assertion 以 base64url 的 WebAuthn JSON 連同 client_id、redirect、PKCE S256、state 送到 /oauth/passkey/authorize")
    func signInAuthorizeBody() async throws {
        try routePasskeySignIn()

        _ = try await auth(FakePasskeyAuthenticator()).signInWithPasskey()

        let body = try json(stub.requests(to: "/oauth/passkey/authorize").first)
        #expect(body["client_id"] as? String == "ios")
        #expect(body["redirect_uri"] as? String == "com.raychiu.mymoney:/oauth/callback")
        #expect(body["code_challenge_method"] as? String == "S256")
        #expect(body["scope"] as? String == "full")
        #expect(((body["state"] as? String)?.count ?? 0) >= 16)
        let response = try #require(body["response"] as? [String: Any])
        #expect(response["id"] as? String == "-_8B")
        #expect(response["rawId"] as? String == "-_8B")
        #expect(response["type"] as? String == "public-key")
        let inner = try #require(response["response"] as? [String: String])
        #expect(inner == [
            "clientDataJSON": "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0In0",
            "authenticatorData": "SZYN",
            "signature": "MEX-",
            "userHandle": "dXNlci1oYW5kbGU",
        ])
    }

    @Test("passkey 登入:授權碼走同一個 /oauth/token 換權杖,code_verifier 的 S256 等於送出的 code_challenge")
    func signInExchangesCode() async throws {
        try routePasskeySignIn()

        let session = try await auth(FakePasskeyAuthenticator()).signInWithPasskey()

        let authorize = try json(stub.requests(to: "/oauth/passkey/authorize").first)
        let token = form(stub.requests(to: "/oauth/token").first)
        #expect(token["grant_type"] == "authorization_code")
        #expect(token["code"] == "fixture-passkey-code")
        #expect(token["redirect_uri"] == "com.raychiu.mymoney:/oauth/callback")
        #expect(token["client_id"] == "ios")
        let verifier = try #require(token["code_verifier"])
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(authorize["code_challenge"] as? String == challenge)
        #expect(session.user.email == "mymoney-ios-test@example.com")
        #expect(session.tokens.refresh == "fake-fixture-refresh-token")
    }

    @Test("passkey 登入時使用者取消:丟 CancellationError,不送授權請求")
    func signInCancelled() async throws {
        try routePasskeySignIn()

        await #expect(throws: CancellationError.self) {
            try await auth(FakePasskeyAuthenticator(cancels: true)).signInWithPasskey()
        }
        #expect(stub.requests(to: "/oauth/passkey/authorize").isEmpty)
    }

    @Test("passkey 驗證失敗(沒有 WWW-Authenticate 的 401)照顯示後端訊息")
    func signInRejected() async throws {
        try stub.route("/auth/passkey/login/options", [(200, "passkey-login-options.json")])
        try stub.route("/oauth/passkey/authorize", [(401, "oauth-passkey-authorize-expired.json")])

        await #expect(throws: RepositoryError.invalidCredentials("Passkey 驗證已過期或重複使用，請重試")) {
            try await auth(FakePasskeyAuthenticator()).signInWithPasskey()
        }
        #expect(stub.requests(to: "/oauth/token").isEmpty)
    }

    @Test("passkey 清單:名稱、建立時間與最後使用時間(Unix 秒,沒用過是 nil)")
    func list() async throws {
        try stub.reply(status: 200, fixture: "passkeys-list.json")

        let passkeys = try await repository().passkeys()

        #expect(stub.requests.first?.httpMethod == "GET")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/passkeys"))
        #expect(passkeys == [
            Passkey(id: PasskeyID("pk-2"), name: "iPhone", createdAt: Date(timeIntervalSince1970: 1_794_716_050), lastUsedAt: nil),
            Passkey(
                id: PasskeyID("pk-1"), name: "MacBook", createdAt: Date(timeIntervalSince1970: 1_793_000_000),
                lastUsedAt: Date(timeIntervalSince1970: 1_794_800_000)
            ),
        ])
    }

    @Test("還沒有 passkey:空清單")
    func emptyList() async throws {
        try stub.reply(status: 200, fixture: "passkeys-empty.json")

        #expect(try await repository().passkeys().isEmpty)
    }

    @Test("建立 passkey:用註冊 options 的 RP ID、challenge、user.id(base64url 解開)與 user.name 向驗證器要 registration")
    func createAsksAuthenticator() async throws {
        try stub.route("/auth/passkey/register/options", [(200, "passkey-register-options.json")])
        try stub.route("/auth/passkey/register/verify", [(201, "passkey-register-verify.json")])
        let authenticator = FakePasskeyAuthenticator()

        try await repository(authenticator).create(name: "iPad")

        #expect(stub.requests(to: "/auth/passkey/register/options").first?.httpMethod == "POST")
        #expect(authenticator.registrations == [.init(
            relyingPartyID: "my-money-onion.pages.dev",
            challenge: Data(base64Encoded: "RjN4vnVQsAme2Bo+z1DyK+0KH8XXuXBaBVP/3AznRMM=")!,
            userID: Data("AjuuZcf6E520BImxh3SNKDeF2wgnFsiU".utf8),
            userName: "mymoney-ios-test@example.com"
        )])
    }

    @Test("建立 passkey:registration 以 base64url 的 WebAuthn JSON 連同名稱送到 /auth/passkey/register/verify")
    func createVerifyBody() async throws {
        try stub.route("/auth/passkey/register/options", [(200, "passkey-register-options.json")])
        try stub.route("/auth/passkey/register/verify", [(201, "passkey-register-verify.json")])

        try await repository().create(name: "iPad")

        let body = try json(stub.requests(to: "/auth/passkey/register/verify").first)
        #expect(body["name"] as? String == "iPad")
        let response = try #require(body["response"] as? [String: Any])
        #expect(response["id"] as? String == "-_8C")
        #expect(response["rawId"] as? String == "-_8C")
        #expect(response["type"] as? String == "public-key")
        #expect(response["response"] as? [String: String] == [
            "clientDataJSON": "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIn0",
            "attestationObject": "o2P_",
        ])
    }

    @Test("建立 passkey 時使用者取消:丟 CancellationError,不送驗證請求")
    func createCancelled() async throws {
        try stub.route("/auth/passkey/register/options", [(200, "passkey-register-options.json")])

        await #expect(throws: CancellationError.self) {
            try await repository(FakePasskeyAuthenticator(cancels: true)).create(name: "iPad")
        }
        #expect(stub.requests(to: "/auth/passkey/register/verify").isEmpty)
    }

    @Test("改名:PATCH /auth/passkeys/:id 帶 name")
    func rename() async throws {
        try stub.reply(status: 200, fixture: "passkey-rename.json")

        try await repository().rename(PasskeyID("pk-1"), to: "工作用 Mac")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url == stub.baseURL.appending(path: "auth/passkeys/pk-1"))
        #expect(try json(request)["name"] as? String == "工作用 Mac")
    }

    @Test("改名不存在的 passkey:「找不到指定的 Passkey」原樣傳遞")
    func renameNotFound() async throws {
        try stub.reply(status: 404, fixture: "passkey-rename-not-found.json")

        await #expect(throws: RepositoryError.rejected("找不到指定的 Passkey")) {
            try await repository().rename(PasskeyID("missing"), to: "x")
        }
    }

    @Test("刪除:DELETE /auth/passkeys/:id")
    func delete() async throws {
        try stub.reply(status: 200, fixture: "passkey-delete.json")

        try await repository().delete(PasskeyID("pk-1"))

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/passkeys/pk-1"))
    }
}
