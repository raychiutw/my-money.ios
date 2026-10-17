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
        let dto: MessageDTO = try await client.send("POST", "/households/reimburse", body: ReimburseBody(reimbursement))
        return dto.message
    }

    /// 回應只有最上層的 `{success, message}`。
    public func unlinkAdvance(_ id: TransactionID) async throws -> String {
        try await client.sendForMessage("POST", "/households/advances/\(id.rawValue)/unlink") ?? "已解除報銷，該筆明細已退回待報銷"
    }

    public func markAdvancesSettled(for memberID: UserID, ids: [TransactionID]) async throws -> String {
        let dto: MessageDTO = try await client.send(
            "POST", "/households/advances/mark-settled", body: MarkSettledBody(targetUserID: memberID.rawValue, ids: ids)
        )
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
        /// 718ace9 起的欄位(UTC);舊的回應沒有。
        let createdAt: String?
        /// `expense` 或 `income`(公帳退款);舊的回應沒有時是支出。
        let type: String?
        /// 信用卡出帳狀態(上游 ADR 0029);非信用卡或舊的回應沒有。
        let isBilled: Int?
        let deferToNextStatement: Int?
        /// 已結清明細才有:撥款流水的 ID,或 `EXTERNAL_SETTLED`(已額外處理)。
        let reimbursementID: String?

        enum CodingKeys: String, CodingKey {
            case id, date, category, note, amount, type
            case accountName = "account_name"
            case accountType = "account_type"
            case createdAt = "created_at"
            case isBilled = "is_billed"
            case deferToNextStatement = "defer_to_next_statement"
            case reimbursementID = "reimbursement_id"
        }
    }

    struct ReceivingAccountDTO: Decodable {
        let id: String
        let name: String
        let type: String
    }

    struct ReimbursementDTO: Decodable {
        let id: String
        let date: String
        let amount: Decimal
        let note: String?
        let accountName: String
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, date, amount, note
            case accountName = "account_name"
            case createdAt = "created_at"
        }
    }

    let userID: String
    let userName: String
    let totalAdvanced: Decimal
    let totalReimbursed: Decimal
    let pendingReimburse: Decimal
    let advanceItems: [ItemDTO]?
    let reimbursementItems: [ReimbursementDTO]?
    /// `b1382f4` 起才有;舊的回應沒有這個欄位。
    let receivingAccounts: [ReceivingAccountDTO]?
    /// 上游 ADR 0027 起;舊的回應沒有這三個欄位。
    let settledItems: [ItemDTO]?
    let linkedReimbursed: Decimal?
    let unlinkedReimbursed: Decimal?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userName = "user_name"
        case totalAdvanced = "total_advanced"
        case totalReimbursed = "total_reimbursed"
        case pendingReimburse = "pending_reimburse"
        case advanceItems = "advance_items"
        case reimbursementItems = "reimbursement_items"
        case receivingAccounts = "receiving_accounts"
        case settledItems = "settled_items"
        case linkedReimbursed = "linked_reimbursed"
        case unlinkedReimbursed = "unlinked_reimbursed"
    }

    func advance() throws -> HouseholdAdvance {
        HouseholdAdvance(
            memberID: UserID(userID),
            memberName: userName,
            totalAdvanced: Money(totalAdvanced),
            totalReimbursed: Money(totalReimbursed),
            pendingReimbursement: Money(pendingReimburse),
            advanceItems: try (advanceItems ?? []).map { try Self.item($0) },
            reimbursementItems: try (reimbursementItems ?? []).map { item in
                guard let date = CalendarDay(iso: item.date) else { throw RepositoryError.unreadableResponse }
                return ReimbursementItem(
                    id: TransactionID(item.id), date: date, amount: Money(item.amount), note: item.note ?? "",
                    accountName: item.accountName, recordedAt: RecordedTime.date(fromBackend: item.createdAt)
                )
            },
            // 可收款帳戶只有銀行存款帳戶和現金錢包;其他類型(信用卡或不認得的)略過那一筆。
            receivingAccounts: (receivingAccounts ?? []).compactMap { account in
                guard let kind = Self.kind(account.type), kind != .creditCard else { return nil }
                return ReceivingAccount(id: AccountID(account.id), name: account.name, kind: kind)
            },
            settledItems: try (settledItems ?? []).map { dto in
                SettledAdvanceItem(item: try Self.item(dto), settlement: Self.settlement(dto.reimbursementID))
            },
            linkedReimbursed: Money(linkedReimbursed ?? 0),
            unlinkedReimbursed: Money(unlinkedReimbursed ?? 0)
        )
    }

    private static func item(_ dto: ItemDTO) throws -> AdvanceItem {
        guard let date = CalendarDay(iso: dto.date) else { throw RepositoryError.unreadableResponse }
        let accountKind = Self.kind(dto.accountType)
        // 信用卡出帳狀態只有扣款帳戶是信用卡時才有意義;舊的回應沒有旗標就不標示。
        let billing: BillingStatus? = accountKind == .creditCard && dto.isBilled != nil
            ? BillingStatus(isBilled: dto.isBilled == 1, defersToNextStatement: dto.deferToNextStatement == 1) : nil
        return AdvanceItem(
            id: TransactionID(dto.id), date: date, category: TransactionCategory(dto.category),
            note: dto.note ?? "", amount: Money(dto.amount), accountName: dto.accountName,
            accountKind: accountKind, recordedAt: RecordedTime.date(fromBackend: dto.createdAt),
            kind: dto.type == "income" ? .refund : .expense, billing: billing
        )
    }

    private static func settlement(_ reimbursementID: String?) -> AdvanceSettlement {
        switch ReimbursementMarker(reimbursementID) {
        case .handledSeparately: .handledSeparately
        case .reimbursed(let id): .reimbursed(id)
        // 已結清明細一定有關聯;空的(不該發生)當作對不到撥款的已報銷。
        case .none: .reimbursed(TransactionID(""))
        }
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

/// `POST /households/advances/mark-settled` 的 body。明細 ID 排序固定。
private struct MarkSettledBody: Encodable {
    let targetUserID: String
    let advanceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case targetUserID = "target_user_id"
        case advanceIDs = "advance_ids"
    }

    init(targetUserID: String, ids: [TransactionID]) {
        self.targetUserID = targetUserID
        advanceIDs = ids.map(\.rawValue).sorted()
    }
}

private struct ReimburseBody: Encodable {
    let targetUserID: String
    let fromAccountID: String
    let toAccountID: String
    let amount: Decimal
    let date: String
    let note: String
    /// 勾選的代墊明細;沒勾選時整個欄位不送(後端有容錯)。
    let advanceIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case amount, date, note
        case advanceIDs = "advance_ids"
        case targetUserID = "target_user_id"
        case fromAccountID = "from_account_id"
        case toAccountID = "to_account_id"
    }

    init(_ reimbursement: Reimbursement) {
        advanceIDs = reimbursement.advanceIDs.isEmpty ? nil : reimbursement.advanceIDs.map(\.rawValue)
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
