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

    public func advances() async throws -> [HouseholdAdvance] {
        let dtos: [AdvanceDTO] = try await client.get("/households/advances")
        return try dtos.map { try $0.advance() }
    }

    public func reimburse(_ reimbursement: Reimbursement) async throws -> String {
        let dto: ReimburseDTO = try await client.send("POST", "/households/reimburse", body: ReimburseBody(reimbursement))
        return dto.message
    }
}

/// `GET /households/advances` 的一筆(snake_case)。
private struct AdvanceDTO: Decodable {
    struct ItemDTO: Decodable {
        let id: String
        let date: String
        let category: String
        let note: String?
        let amount: Decimal
        let accountName: String
        let accountType: String

        enum CodingKeys: String, CodingKey {
            case id, date, category, note, amount
            case accountName = "account_name"
            case accountType = "account_type"
        }
    }

    struct ReimbursementDTO: Decodable {
        let id: String
        let date: String
        let amount: Decimal
        let note: String?
        let accountName: String

        enum CodingKeys: String, CodingKey {
            case id, date, amount, note
            case accountName = "account_name"
        }
    }

    let userID: String
    let userName: String
    let totalAdvanced: Decimal
    let totalReimbursed: Decimal
    let pendingReimburse: Decimal
    let advanceItems: [ItemDTO]?
    let reimbursementItems: [ReimbursementDTO]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userName = "user_name"
        case totalAdvanced = "total_advanced"
        case totalReimbursed = "total_reimbursed"
        case pendingReimburse = "pending_reimburse"
        case advanceItems = "advance_items"
        case reimbursementItems = "reimbursement_items"
    }

    func advance() throws -> HouseholdAdvance {
        HouseholdAdvance(
            memberID: UserID(userID),
            memberName: userName,
            totalAdvanced: Money(totalAdvanced),
            totalReimbursed: Money(totalReimbursed),
            pendingReimbursement: Money(pendingReimburse),
            advanceItems: try (advanceItems ?? []).map { item in
                guard let date = CalendarDay(iso: item.date) else { throw RepositoryError.unreadableResponse }
                return AdvanceItem(
                    id: TransactionID(item.id), date: date, category: TransactionCategory(item.category),
                    note: item.note ?? "", amount: Money(item.amount), accountName: item.accountName,
                    accountKind: Self.kind(item.accountType)
                )
            },
            reimbursementItems: try (reimbursementItems ?? []).map { item in
                guard let date = CalendarDay(iso: item.date) else { throw RepositoryError.unreadableResponse }
                return ReimbursementItem(
                    id: TransactionID(item.id), date: date, amount: Money(item.amount), note: item.note ?? "",
                    accountName: item.accountName
                )
            }
        )
    }

    /// 帳戶已刪除時後端回 `other`。
    private static func kind(_ type: String) -> AccountKind? {
        switch type {
        case "cash": .cash
        case "bank": .bank
        case "credit_card": .creditCard
        default: nil
        }
    }
}

/// 撥款報銷的結果：訊息在 `data.message`。
private struct ReimburseDTO: Decodable {
    let message: String
}

private struct ReimburseBody: Encodable {
    let targetUserID: String
    let fromAccountID: String
    let toAccountID: String
    let amount: Decimal
    let date: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case amount, date, note
        case targetUserID = "target_user_id"
        case fromAccountID = "from_account_id"
        case toAccountID = "to_account_id"
    }

    init(_ reimbursement: Reimbursement) {
        targetUserID = reimbursement.memberID.rawValue
        fromAccountID = reimbursement.fromAccountID.rawValue
        toAccountID = reimbursement.toAccountID.rawValue
        amount = reimbursement.amount.amount
        date = reimbursement.date.iso
        note = reimbursement.note
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
