import CryptoKit
import Foundation
import MyMoneyDomain

/// 登入、登出與刪除帳號的 URLSession 實作。登入走上游的 OAuth 2.1 授權碼 + PKCE(ADR 0038,#334):
/// client `ios` 與 redirect URI 是上游寫死的。
public struct LiveAuthRepository: AuthRepository {
    private static let callbackScheme = "com.raychiu.mymoney"
    private static let redirectURI = "com.raychiu.mymoney:/oauth/callback"

    private let client: APIClient
    private let browser: any BrowserAuthorizer
    private let loginPage: @Sendable () async -> LoginPageAppearance

    /// `loginPage`:每次開登入視窗時取一次登入頁的外觀(生物辨識種類、字級倍數),由 composition root 提供(#344)。
    public init(
        client: APIClient, browser: any BrowserAuthorizer,
        loginPage: @escaping @Sendable () async -> LoginPageAppearance = { LoginPageAppearance() }
    ) {
        self.client = client
        self.browser = browser
        self.loginPage = loginPage
    }

    public func signIn(registering: Bool) async throws -> SignInResult {
        let verifier = Self.randomBase64URL(byteCount: 32)
        let state = Self.randomBase64URL(byteCount: 16)
        var authorize = URLComponents(url: client.url(for: "/oauth/authorize"), resolvingAgainstBaseURL: false)!
        authorize.queryItems = [
            URLQueryItem(name: "client_id", value: APIClient.oauthClientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "full"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ] + (registering ? [URLQueryItem(name: "mode", value: "register")] : [])
            + (await loginPage()).queryItems

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

        return SignInResult(session: try await exchange(code: code, verifier: verifier), biometric: params["biometric"] == "1")
    }

    /// 用授權碼換權杖(`POST /oauth/token`)。
    private func exchange(code: String, verifier: String) async throws -> Session {
        // 每次登入換一把新的 DPoP 金鑰,換碼時用它綁定這個登入工作階段(#337);換碼成功才取代保存的(#364)。
        let key = client.newDPoPKey()
        let data = try await client.postForm("/oauth/token", [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": APIClient.oauthClientID,
            "code_verifier": verifier,
        ], signingWith: key)
        guard
            let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
            let user = Self.user(fromAccessToken: token.accessToken)
        else {
            throw RepositoryError.unreadableResponse
        }
        client.bindDPoPKey(key)
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
        client.deleteDPoPKey()
    }

    /// 沿用 `APIClient` 的 refresh:輪替、`invalid_grant`(或本機沒有金鑰時的 `invalid_dpop_proof`)登出並刪 DPoP 金鑰、網路錯誤不登出都一樣。
    public func refreshSession() async throws {
        try await client.refreshSession()
    }

    /// 後端只回 `{success, message}`,沒有 `data`。
    public func deleteAccount() async throws {
        try await client.send("DELETE", "/auth/account")
        client.deleteDPoPKey()
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

/// 上游登入頁(`GET /oauth/authorize`)的純外觀參數(上游 ADR 0042,#344)。
public struct LoginPageAppearance: Sendable {
    /// 這台裝置的生物辨識種類:有生物辨識時登入頁才顯示 passkey 登入按鈕(上游按鈕文字「用 Face ID 登入」)。
    public var biometry: DeviceAuthCapability
    /// Dynamic Type 的 body 字級相對預設 17pt 的倍數。
    public var fontScale: Double

    public init(biometry: DeviceAuthCapability = .unavailable, fontScale: Double = 1) {
        self.biometry = biometry
        self.fontScale = fontScale
    }

    /// 只有生物辨識才帶 `biometry`;上游只接受 faceid/touchid/opticid。
    var queryItems: [URLQueryItem] {
        let biometry: String? = switch self.biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcodeOnly, .unavailable: nil
        }
        // 上游夾在 1～3.1,不合法或沒帶視為 1;小數點固定用「.」,不跟著使用者語系。
        let scale = (min(max(fontScale, 1), 3.1) * 100).rounded() / 100
        let fontScale = scale > 1
            ? scale.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            : nil
        return [("biometry", biometry), ("font_scale", fontScale)].compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
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

/// 存取權杖 payload 裡顯示用的部分。
private struct AccessTokenClaims: Decodable {
    let sub: String
    let email: String
    let name: String
}
