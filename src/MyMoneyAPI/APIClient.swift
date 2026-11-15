import CryptoKit
import Foundation
import MyMoneyDomain
import Synchronization

/// 呼叫後端 API 的唯一入口。envelope 與錯誤映射都在這裡處理，各個 repository 只管自己的 DTO。
public struct APIClient: Sendable {
    /// prod 後端;Debug 與 Release 相同(後端不歸我們管，見 ADR-0001)。
    public static let productionBaseURL = URL(string: "https://my-money-api.onion523.workers.dev")!

    private let baseURL: URL
    private let urlSession: URLSession
    private let session: any SessionProvider
    private let userAgent: String
    /// 同一時間只送一個 refresh;複製出去的 `APIClient` 共用同一個(#335)。
    private let refresher = SingleFlight()
    /// DPoP 金鑰(#337);`nil` 時不綁定,照舊用 `Bearer`。
    private let dpopKeys: (any DPoPKeyStore)?
    /// 伺服器時間減本機時間(秒):proof 的 `iat` 用伺服器的時間,手機時間不準也不會被拒。複製出去的共用同一個。
    private let clockOffset = ClockOffset()

    /// - Parameter deviceModel: `UIDevice.current.model`(iPhone／iPad),放進 User-Agent。
    public init(
        baseURL: URL = APIClient.productionBaseURL,
        urlSession: URLSession = .shared,
        session: any SessionProvider,
        deviceModel: String = "iPhone",
        dpopKeys: (any DPoPKeyStore)? = nil
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.session = session
        self.dpopKeys = dpopKeys
        userAgent = "MyMoney-iOS (\(deviceModel))"
    }

    /// 送出請求，並取出 `{success, data}` 裡的 `data`。
    package func send<Payload: Decodable>(
        _ method: String,
        _ path: String,
        body: some Encodable
    ) async throws -> Payload {
        let data = try await perform(method, path, body: try JSONEncoder().encode(body))
        return try decodeData(data)
    }

    /// 送出沒有 body 的請求，並取出 `{success, data}` 裡的 `data`(例如產生邀請碼、結帳日出帳作業)。
    package func send<Payload: Decodable>(_ method: String, _ path: String) async throws -> Payload {
        let data = try await perform(method, path, body: nil)
        return try decodeData(data)
    }

    /// 送出 GET,並取出 `{success, data}` 裡的 `data`。
    package func get<Payload: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Payload {
        let data = try await perform("GET", path, query: query, body: nil)
        return try decodeData(data)
    }

    /// 送出 GET,原樣回傳 body(例如 `/export/csv` 回的是 `text/csv`,不是 JSON envelope)。
    /// 401 的處理跟其他請求一樣;非 2xx 時，body 若是 `{success: false, error}` 就原樣傳遞訊息。
    package func getRaw(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await perform("GET", path, query: query, body: nil, expectsEnvelope: false)
    }

    private func decodeData<Payload: Decodable>(_ data: Data) throws -> Payload {
        guard let envelope = try? JSONDecoder().decode(DataEnvelope<Payload>.self, from: data) else {
            throw RepositoryError.unreadableResponse
        }
        return envelope.data
    }

    /// 送出不需要回傳內容的請求，例如只回 `{success, message}` 的 DELETE。
    package func send(_ method: String, _ path: String) async throws {
        _ = try await perform(method, path, body: nil)
    }

    /// 送出沒有 body 的請求,回傳最上層的 `message`(`{success, message}`,沒有 `data`,例如解除報銷);沒有訊息時是 `nil`。
    package func sendForMessage(_ method: String, _ path: String) async throws -> String? {
        let data = try await perform(method, path, body: nil)
        return (try? JSONDecoder().decode(TopLevelMessage.self, from: data))?.message
    }

    /// 送出帶 body、但不需要回傳內容的請求(例如新增後由資料版本機制重抓，不讀回應)。
    package func send(_ method: String, _ path: String, body: some Encodable) async throws {
        _ = try await perform(method, path, body: try JSONEncoder().encode(body))
    }

    /// 送出請求並檢查 envelope 的 `success`;回傳原始 body,讓呼叫端解自己的 `data`。
    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data?,
        expectsEnvelope: Bool = true,
        retried: Bool = false,
        resigned: Bool = false
    ) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 後端用 User-Agent 產生「工作階段」的裝置名稱(上游 parseDeviceName:含 MyMoney-iOS,再看有沒有 iPad)。
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let token = try await accessToken()
        var proof: String?
        if let token {
            proof = try dpopProof(method, url, accessToken: token)
            request.setValue("\(proof == nil ? "Bearer" : "DPoP") \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(proof, forHTTPHeaderField: "DPoP")
        }
        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
            // invalid_token:refresh 後重送一次;重送仍 401 才登出(handleUnauthorized)。
            let challenge = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
            if !retried, let token, challenge.contains("invalid_token") {
                _ = try await accessToken(rejecting: token)
                return try await perform(
                    method, path, query: query, body: body, expectsEnvelope: expectsEnvelope, retried: true, resigned: resigned
                )
            }
            // invalid_dpop_proof:多半是手機時間不準;依回應的 Date 校正後重簽、重送一次,不登出。
            if !resigned, proof != nil, challenge.contains("invalid_dpop_proof") {
                clockOffset.note(response)
                return try await perform(
                    method, path, query: query, body: body, expectsEnvelope: expectsEnvelope, retried: retried, resigned: true
                )
            }
            try await handleUnauthorized(response, data: data)
        }
        if !expectsEnvelope {
            guard (200..<300).contains(statusCode) else {
                let status = try? JSONDecoder().decode(StatusEnvelope.self, from: data)
                throw status?.error.map(RepositoryError.rejected) ?? RepositoryError.unreadableResponse
            }
            return data
        }
        guard let status = try? JSONDecoder().decode(StatusEnvelope.self, from: data) else {
            throw RepositoryError.unreadableResponse
        }
        // 照 web 的判斷:HTTP 狀態不是 2xx,或 `success` 不是 true,都算失敗。
        guard (200..<300).contains(statusCode), status.success else {
            throw RepositoryError.rejected(status.error ?? "請求失敗")
        }
        return data
    }

    /// 後端某個路徑的完整網址(例如給系統登入視窗開的 `/oauth/authorize`)。
    package func url(for path: String) -> URL {
        baseURL.appending(path: path)
    }

    /// OAuth 端點(`/oauth/token`、`/oauth/revoke`):body 是 form-urlencoded、不帶權杖,回應不是 `{success, data}` envelope。
    /// 非 2xx 時照顯示 `{error, error_description}` 的 `error_description`。
    package func postForm(_ path: String, _ form: [String: String]) async throws -> Data {
        let (data, status) = try await sendForm(path, form)
        guard (200..<300).contains(status) else { throw Self.oauthError(data) }
        return data
    }

    /// 有 DPoP 金鑰時帶 proof(換碼與 refresh 由此綁定金鑰);回 `invalid_dpop_proof` 時依 `Date` 校正、重簽送一次
    /// (上游:proof 驗證失敗時不會消費授權碼與更新權杖)。
    private func sendForm(_ path: String, _ form: [String: String], resigned: Bool = false) async throws -> (Data, Int) {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let proof = try dpopProof("POST", url, accessToken: nil)
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.httpBody = Data(form.map { "\(Self.formEncode($0))=\(Self.formEncode($1))" }.joined(separator: "&").utf8)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !resigned, proof != nil, !(200..<300).contains(status),
           (try? JSONDecoder().decode(OAuthErrorResponse.self, from: data))?.error == "invalid_dpop_proof" {
            clockOffset.note(response)
            return try await sendForm(path, form, resigned: true)
        }
        return (data, status)
    }

    /// 登入時產生這次登入工作階段的新金鑰(取代舊的);產生失敗時不綁定,照舊用 `Bearer`(同 web)。
    package func createDPoPKey() {
        if (try? dpopKeys?.create()) == nil { dpopKeys?.delete() }
    }

    /// 登出、`invalid_grant`、刪除帳號時刪掉金鑰。
    package func deleteDPoPKey() {
        dpopKeys?.delete()
    }

    /// DPoP proof(RFC 9449 §4.2);沒有金鑰時是 `nil`。`htu` 不含 query 與 fragment;受保護的請求另帶 `ath`。
    private func dpopProof(_ method: String, _ url: URL, accessToken: String?) throws -> String? {
        guard let key = dpopKeys?.load() else { return nil }
        var htu = URLComponents(url: url, resolvingAgainstBaseURL: false)
        htu?.query = nil
        htu?.fragment = nil
        let point = key.publicKey.rawRepresentation  // x || y
        let header = DPoPHeader(jwk: .init(x: Self.base64URL(point.prefix(32)), y: Self.base64URL(point.suffix(32))))
        let payload = DPoPPayload(
            jti: UUID().uuidString, htm: method, htu: htu?.url?.absoluteString ?? url.absoluteString,
            iat: Int(Date().timeIntervalSince1970 + clockOffset.seconds),
            ath: accessToken.map { Self.base64URL(SHA256.hash(data: Data($0.utf8))) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let signingInput = "\(Self.base64URL(try encoder.encode(header))).\(Self.base64URL(try encoder.encode(payload)))"
        return "\(signingInput).\(Self.base64URL(try key.sign(Data(signingInput.utf8))))"
    }

    private static func base64URL(_ bytes: some Sequence<UInt8>) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func oauthError(_ data: Data) -> RepositoryError {
        let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
        return error.map { RepositoryError.rejected($0.errorDescription ?? $0.error) } ?? RepositoryError.unreadableResponse
    }

    /// 送出前取得可用的存取權杖(#335):沒有(冷啟動)、一分鐘內到期,或剛被 401 拒絕(`rejecting`)時先 refresh。
    /// 別的請求已經換到新的就直接用,不再 refresh。
    private func accessToken(rejecting rejected: String? = nil) async throws -> String? {
        guard let tokens = await session.currentTokens() else { return nil }
        if let access = tokens.access, access != rejected,
           (tokens.accessExpiresAt ?? .distantFuture) > Date().addingTimeInterval(60) {
            return access
        }
        return try await refresher.run { try await refresh() }
    }

    /// `grant_type=refresh_token`:成功時改存輪替後的新更新權杖。只有 `invalid_grant` 才登出;
    /// 網路錯誤與 5xx 照一般錯誤丟出,保留更新權杖(上游 #208)。
    private func refresh() async throws -> String {
        guard let tokens = await session.currentTokens() else { throw RepositoryError.sessionExpired }
        let (data, status) = try await sendForm("/oauth/token", [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refresh,
            "client_id": "ios",  // 上游寫死的 client,跟 LiveAuthRepository 相同
        ])
        guard (200..<300).contains(status) else {
            if (try? JSONDecoder().decode(OAuthErrorResponse.self, from: data))?.error == "invalid_grant" {
                deleteDPoPKey()
                await session.sessionDidExpire()
                throw RepositoryError.sessionExpired
            }
            throw Self.oauthError(data)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw RepositoryError.unreadableResponse
        }
        await session.sessionDidRefresh(SessionTokens(
            access: token.accessToken, refresh: token.refreshToken,
            accessExpiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        ))
        return token.accessToken
    }

    /// form-urlencoded 只保留 RFC 3986 的 unreserved 字元,其餘(包括 `+`、`/`、`=`、`&`)都百分比編碼。
    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// 401 依 `WWW-Authenticate` 判斷，不看路徑(上游 c899f01:`/auth/sessions` 等也走權杖驗證)。
    /// `invalid_token`(refresh 後重送仍被拒)是登入工作階段失效;`invalid_dpop_proof` 只是這次的 proof 不對，不登出;
    /// 沒有 challenge 的 401 是帳密錯誤或「目前密碼錯誤」,照顯示後端訊息。
    private func handleUnauthorized(_ response: URLResponse, data: Data) async throws -> Never {
        let challenge = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "WWW-Authenticate")
        let status = try? JSONDecoder().decode(StatusEnvelope.self, from: data)
        guard let challenge else {
            throw RepositoryError.invalidCredentials(status?.error ?? "Email 或密碼錯誤")
        }
        if challenge.contains("invalid_token") {
            await session.sessionDidExpire()
            throw RepositoryError.sessionExpired
        }
        throw RepositoryError.rejected(status?.error ?? "請求失敗")
    }
}

/// 同一時間只執行一個(refresh):進行中再呼叫的人等同一個結果。
private actor SingleFlight {
    private var inFlight: Task<String, any Error>?

    func run(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

/// 伺服器與本機的時差(秒),由 `invalid_dpop_proof` 回應的 `Date` 算出。
private final class ClockOffset: Sendable {
    private let offset = Mutex<TimeInterval>(0)

    var seconds: TimeInterval { offset.withLock { $0 } }

    func note(_ response: URLResponse) {
        guard
            let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"),
            let server = try? Date(header, strategy: .http)
        else { return }
        offset.withLock { $0 = server.timeIntervalSinceNow }
    }
}

/// DPoP proof 的 JOSE header:`jwk` 只有公鑰。
private struct DPoPHeader: Encodable {
    struct JWK: Encodable {
        var kty = "EC"
        var crv = "P-256"
        let x: String
        let y: String
    }

    var typ = "dpop+jwt"
    var alg = "ES256"
    let jwk: JWK
}

private struct DPoPPayload: Encodable {
    let jti: String
    let htm: String
    let htu: String
    let iat: Int
    /// 只有受保護的請求才有(`nil` 不輸出)。
    let ath: String?
}

/// 每種 envelope 都有的部分:`{success}`,失敗時另有 `error`。
private struct StatusEnvelope: Decodable {
    let success: Bool
    let error: String?
}

/// OAuth 端點的錯誤(RFC 6749 §5.2):`{error, error_description}`。
private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// 最上層有 `message` 的回應:`{success, message}`。
private struct TopLevelMessage: Decodable {
    let message: String?
}

/// 成功回應的 envelope:`{success: true, data}`。
private struct DataEnvelope<Payload: Decodable>: Decodable {
    let data: Payload
}
