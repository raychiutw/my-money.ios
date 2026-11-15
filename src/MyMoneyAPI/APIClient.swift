import Foundation
import MyMoneyDomain

/// 呼叫後端 API 的唯一入口。envelope 與錯誤映射都在這裡處理，各個 repository 只管自己的 DTO。
public struct APIClient: Sendable {
    /// prod 後端;Debug 與 Release 相同(後端不歸我們管，見 ADR-0001)。
    public static let productionBaseURL = URL(string: "https://my-money-api.onion523.workers.dev")!

    private let baseURL: URL
    private let urlSession: URLSession
    private let session: any SessionProvider
    private let userAgent: String

    /// - Parameter deviceModel: `UIDevice.current.model`(iPhone／iPad),放進 User-Agent。
    public init(
        baseURL: URL = APIClient.productionBaseURL,
        urlSession: URLSession = .shared,
        session: any SessionProvider,
        deviceModel: String = "iPhone"
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.session = session
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
    package func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await perform(method, path, query: query, body: nil)
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
        expectsEnvelope: Bool = true
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
        if let token = await session.currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
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
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(form.map { "\(Self.formEncode($0))=\(Self.formEncode($1))" }.joined(separator: "&").utf8)
        let (data, response) = try await urlSession.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            throw error.map { RepositoryError.rejected($0.errorDescription ?? $0.error) } ?? RepositoryError.unreadableResponse
        }
        return data
    }

    /// form-urlencoded 只保留 RFC 3986 的 unreserved 字元,其餘(包括 `+`、`/`、`=`、`&`)都百分比編碼。
    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// 401 依 `WWW-Authenticate` 判斷，不看路徑(上游 c899f01:`/auth/sessions` 等也走權杖驗證)。
    /// `invalid_token` 是權杖失效;`invalid_dpop_proof` 只是這次的 proof 不對，不登出;
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
