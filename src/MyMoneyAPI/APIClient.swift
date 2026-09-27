import Foundation
import MyMoneyDomain

/// 呼叫後端 API 的唯一入口。envelope 與錯誤映射都在這裡處理，各個 repository 只管自己的 DTO。
public struct APIClient: Sendable {
    /// prod 後端;Debug 與 Release 相同(後端不歸我們管，見 ADR-0001)。
    public static let productionBaseURL = URL(string: "https://my-money-api.onion523.workers.dev")!

    private let baseURL: URL
    private let urlSession: URLSession
    private let session: any SessionProvider

    public init(
        baseURL: URL = APIClient.productionBaseURL,
        urlSession: URLSession = .shared,
        session: any SessionProvider
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.session = session
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

    /// 送出 GET,並取出 `{success, data}` 裡的 `data`。
    package func get<Payload: Decodable>(_ path: String) async throws -> Payload {
        let data = try await perform("GET", path, body: nil)
        return try decodeData(data)
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

    /// 送出帶 body、但不需要回傳內容的請求(例如新增後由資料版本機制重抓，不讀回應)。
    package func send(_ method: String, _ path: String, body: some Encodable) async throws {
        _ = try await perform(method, path, body: try JSONEncoder().encode(body))
    }

    /// 送出請求並檢查 envelope 的 `success`;回傳原始 body,讓呼叫端解自己的 `data`。
    private func perform(_ method: String, _ path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let token = await session.currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 跟 web 一樣:/auth/* 的 401 是「Email 或密碼錯誤」,其餘的 401 代表 token 失效。
        if statusCode == 401, !path.hasPrefix("/auth/") {
            await session.sessionDidExpire()
            throw RepositoryError.sessionExpired
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
}

/// 每種 envelope 都有的部分:`{success}`,失敗時另有 `error`。
private struct StatusEnvelope: Decodable {
    let success: Bool
    let error: String?
}

/// 成功回應的 envelope:`{success: true, data}`。
private struct DataEnvelope<Payload: Decodable>: Decodable {
    let data: Payload
}
