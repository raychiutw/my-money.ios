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

    public init(client: APIClient, browser: any BrowserAuthorizer) {
        self.client = client
        self.browser = browser
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
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
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

        // 每次登入換一把新的 DPoP 金鑰,換碼時用它綁定這個登入工作階段(#337)。
        client.createDPoPKey()
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
        client.deleteDPoPKey()
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
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard
            let data = Data(base64Encoded: base64),
            let claims = try? JSONDecoder().decode(AccessTokenClaims.self, from: data)
        else { return nil }
        return User(id: UserID(claims.sub), email: claims.email, name: claims.name)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        base64URL(SymmetricKey(size: SymmetricKeySize(bitCount: byteCount * 8)).withUnsafeBytes { Data($0) })
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
