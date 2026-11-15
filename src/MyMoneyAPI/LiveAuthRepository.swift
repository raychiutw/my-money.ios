import CryptoKit
import Foundation
import MyMoneyDomain

/// 登入、登出與刪除帳號的 URLSession 實作。登入走上游的 OAuth 2.1 授權碼 + PKCE(ADR 0038,#334):
/// client `ios` 與 redirect URI 是上游寫死的。
public struct LiveAuthRepository: AuthRepository {
    private static let clientID = "ios"
    private static let callbackScheme = "com.raychiu.mymoney"
    private static let redirectURI = "com.raychiu.mymoney:/oauth/callback"

    private let client: APIClient
    private let browser: any BrowserAuthorizer
    private let passkeys: any PasskeyAuthenticator

    public init(client: APIClient, browser: any BrowserAuthorizer, passkeys: any PasskeyAuthenticator) {
        self.client = client
        self.browser = browser
        self.passkeys = passkeys
    }

    public func signIn(registering: Bool) async throws -> Session {
        let verifier = Self.randomBase64URL(byteCount: 32)
        let state = Self.randomBase64URL(byteCount: 16)
        var authorize = URLComponents(url: client.url(for: "/oauth/authorize"), resolvingAgainstBaseURL: false)!
        authorize.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "full"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ] + (registering ? [URLQueryItem(name: "mode", value: "register")] : [])

        let callback = try await browser.authorize(url: authorize.url!, callbackScheme: Self.callbackScheme)
        let params = Dictionary(
            (URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        ) { first, _ in first }
        if let error = params["error"] {
            throw RepositoryError.rejected(params["error_description"] ?? error)
        }
        guard params["state"] == state, let code = params["code"] else {
            throw RepositoryError.rejected("登入失敗，請再試一次")
        }

        return try await exchange(code: code, verifier: verifier)
    }

    /// WebAuthn 授權橋接(#339):原生 assertion 連同 PKCE 送到 `POST /oauth/passkey/authorize` 換授權碼,
    /// 再走跟系統登入視窗同一個 `/oauth/token`。不用相容端點 `/auth/passkey/login/verify`。
    public func signInWithPasskey() async throws -> Session {
        let options: LoginOptionsDTO = try await client.send("POST", "/auth/passkey/login/options", body: [String: String]())
        guard let challenge = Data(base64URLEncoded: options.challenge) else { throw RepositoryError.unreadableResponse }
        let assertion = try await passkeys.assertion(relyingPartyID: options.rpId, challenge: challenge)
        let verifier = Self.randomBase64URL(byteCount: 32)
        // 回應直接是 JSON(不經 callback 導回),state 只是照上游的參數帶上,不用比對。
        let grant: AuthorizationCodeDTO = try await client.send("POST", "/oauth/passkey/authorize", body: PasskeyAuthorizeRequest(
            response: WebAuthnCredentialJSON(credentialID: assertion.credentialID, response: AssertionJSON(
                clientDataJSON: assertion.clientDataJSON.base64URLEncodedString(),
                authenticatorData: assertion.authenticatorData.base64URLEncodedString(),
                signature: assertion.signature.base64URLEncodedString(),
                userHandle: assertion.userHandle?.base64URLEncodedString()
            )),
            clientID: Self.clientID, redirectURI: Self.redirectURI, codeChallenge: Self.codeChallenge(verifier),
            codeChallengeMethod: "S256", state: Self.randomBase64URL(byteCount: 16), scope: "full"
        ))
        return try await exchange(code: grant.code, verifier: verifier)
    }

    /// 用授權碼換權杖(`POST /oauth/token`);系統登入視窗與 passkey 共用。
    private func exchange(code: String, verifier: String) async throws -> Session {
        let data = try await client.postForm("/oauth/token", [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ])
        guard
            let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
            let user = Self.user(fromAccessToken: token.accessToken)
        else {
            throw RepositoryError.unreadableResponse
        }
        return Session(
            user: user,
            tokens: SessionTokens(
                access: token.accessToken, refresh: token.refreshToken,
                accessExpiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
            )
        )
    }

    /// 撤銷這台的登入工作階段;失敗也不丟錯(呼叫端已經清掉本機的登入狀態)。
    public func signOut(_ session: Session) async {
        _ = try? await client.postForm("/oauth/revoke", ["token": session.tokens.refresh])
    }

    /// 後端只回 `{success, message}`,沒有 `data`。
    public func deleteAccount() async throws {
        try await client.send("DELETE", "/auth/account")
    }

    /// token 回應沒有使用者資料:從存取權杖(JWT)的 payload 取 `sub`、`email`、`name`,只用於顯示,不驗章(後端驗)。
    private static func user(fromAccessToken token: String) -> User? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard
            let data = Data(base64URLEncoded: String(parts[1])),
            let claims = try? JSONDecoder().decode(AccessTokenClaims.self, from: data)
        else { return nil }
        return User(id: UserID(claims.sub), email: claims.email, name: claims.name)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        SymmetricKey(size: SymmetricKeySize(bitCount: byteCount * 8)).withUnsafeBytes { Data($0) }.base64URLEncodedString()
    }

    private static func codeChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

/// `POST /oauth/token` 成功的回應(不是 envelope):`{access_token, token_type, expires_in, refresh_token, scope}`。
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// SimpleWebAuthn 的登入 options 裡用得到的部分;`challenge` 是 base64url。
private struct LoginOptionsDTO: Decodable {
    let rpId: String
    let challenge: String
}

private struct AssertionJSON: Encodable {
    let clientDataJSON: String
    let authenticatorData: String
    let signature: String
    let userHandle: String?
}

private struct PasskeyAuthorizeRequest: Encodable {
    let response: WebAuthnCredentialJSON<AssertionJSON>
    let clientID: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let state: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case response, state, scope
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
    }
}

/// `POST /oauth/passkey/authorize` 的 `data`。
private struct AuthorizationCodeDTO: Decodable {
    let code: String
}

/// 存取權杖 payload 裡顯示用的部分。
private struct AccessTokenClaims: Decodable {
    let sub: String
    let email: String
    let name: String
}
