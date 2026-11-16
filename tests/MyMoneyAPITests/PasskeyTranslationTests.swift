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

    private func auth(browser: FakeBrowserAuthorizer) -> LiveAuthRepository {
        LiveAuthRepository(client: client(), browser: browser)
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

    /// 登入頁的「用 Face ID 登入」改為送出帳密(#353),不再導回 passkey_requested;收到就照一般 error 顯示。
    @Test("導回 passkey_requested 不再改走原生 passkey:照顯示 error_description,不送任何請求")
    func passkeyRequestedNoLongerSwitchesToPasskey() async throws {
        await #expect(throws: RepositoryError.rejected("x")) {
            try await auth(browser: FakeBrowserAuthorizer(.passkeyRequested)).signIn(registering: false)
        }
        #expect(stub.requests.isEmpty)
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
