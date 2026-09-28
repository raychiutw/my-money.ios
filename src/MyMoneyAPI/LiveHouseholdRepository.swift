import Foundation
import MyMoneyDomain

/// `/households` 的 URLSession 實作。
public struct LiveHouseholdRepository: HouseholdRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func current() async throws -> Household? {
        let dto: CurrentDTO = try await client.get("/households/current")
        guard let household = dto.household else { return nil }
        guard let myRole = dto.myRole.flatMap(HouseholdRole.init(rawValue:)) else { throw RepositoryError.unreadableResponse }
        return Household(name: household.name, myRole: myRole, members: try dto.members.map { try $0.member() })
    }

    public func create(name: String) async throws {
        try await client.send("POST", "/households", body: ["name": name])
    }

    public func join(code: String) async throws {
        try await client.send("POST", "/households/join", body: ["code": code])
    }

    public func invite() async throws -> HouseholdInvitation {
        let dto: InvitationDTO = try await client.send("POST", "/households/invite")
        // 後端用 `toISOString()`,有毫秒。
        guard let expiresAt = try? Date(dto.expiresAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) else {
            throw RepositoryError.unreadableResponse
        }
        return HouseholdInvitation(code: dto.code, expiresAt: expiresAt)
    }

    /// 後端只回 `{success, message}`,沒有 `data`。
    public func leave() async throws {
        try await client.send("DELETE", "/households/leave")
    }

    public func removeMember(_ userID: UserID) async throws {
        try await client.send("DELETE", "/households/members/\(userID.rawValue)")
    }
}

private struct CurrentDTO: Decodable {
    struct HouseholdDTO: Decodable {
        let name: String
    }

    let household: HouseholdDTO?
    let members: [MemberDTO]
    let myRole: String?
}

private struct MemberDTO: Decodable {
    let userID: String
    let name: String
    let email: String
    let role: String
    /// SQLite 的 `datetime('now')`:UTC 的「YYYY-MM-DD HH:MM:SS」。
    let joinedAt: String

    enum CodingKeys: String, CodingKey {
        case name, email, role
        case userID = "user_id"
        case joinedAt = "joined_at"
    }

    func member() throws -> HouseholdMember {
        guard
            let role = HouseholdRole(rawValue: role),
            let joinedAt = try? Date(joinedAt.replacingOccurrences(of: " ", with: "T") + "Z", strategy: .iso8601)
        else {
            throw RepositoryError.unreadableResponse
        }
        return HouseholdMember(userID: UserID(userID), name: name, email: email, role: role, joinedAt: joinedAt)
    }
}

private struct InvitationDTO: Decodable {
    let code: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
}
