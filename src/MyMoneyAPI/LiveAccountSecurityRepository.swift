import Foundation
import MyMoneyDomain

/// 帳號安全(`/auth/sessions`、`/auth/password`)的 URLSession 實作(#338)。
/// 這些端點也走權杖驗證:401 的判斷在 `APIClient`(沒有 `WWW-Authenticate` 的「目前密碼錯誤」不登出)。
public struct LiveAccountSecurityRepository: AccountSecurityRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func loginSessions() async throws -> [LoginSession] {
        let dtos: [LoginSessionDTO] = try await client.get("/auth/sessions")
        return dtos.map { dto in
            LoginSession(
                id: LoginSessionID(dto.id), client: dto.clientID, deviceName: dto.deviceName,
                createdAt: Date(timeIntervalSince1970: dto.createdAt), lastUsedAt: Date(timeIntervalSince1970: dto.lastUsedAt),
                isCurrent: dto.current
            )
        }
    }

    public func signOut(_ id: LoginSessionID) async throws {
        try await client.send("DELETE", "/auth/sessions/\(id.rawValue)")
    }

    public func signOutOtherSessions() async throws {
        try await client.send("DELETE", "/auth/sessions", query: [URLQueryItem(name: "scope", value: "others")])
    }

    public func changePassword(current: String, new: String) async throws -> String {
        let dto: MessageDTO = try await client.send(
            "POST", "/auth/password", body: ["current_password": current, "new_password": new]
        )
        return dto.message
    }
}

/// `GET /auth/sessions` 的一筆:snake_case,時間是 Unix 秒。
private struct LoginSessionDTO: Decodable {
    let id: String
    let clientID: String
    let deviceName: String
    let createdAt: TimeInterval
    let lastUsedAt: TimeInterval
    let current: Bool

    enum CodingKeys: String, CodingKey {
        case id, current
        case clientID = "client_id"
        case deviceName = "device_name"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}
