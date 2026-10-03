import Foundation
import MyMoneyDomain

/// `/recurring` 的 URLSession 實作。
public struct LiveRecurringRepository: RecurringRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// 一律明確帶 `scope`(`all` 也帶)，不依賴後端的預設範圍。
    public func items(scope: ViewScope) async throws -> [RecurringItem] {
        let dtos: [RecurringItemDTO] = try await client.get("/recurring", query: [URLQueryItem(name: "scope", value: scope.rawValue)])
        return try dtos.map { try $0.item() }
    }

    public func amortization(scope: ViewScope) async throws -> RecurringAmortization {
        let dto: AmortizationDTO = try await client.get(
            "/recurring/amortize", query: [URLQueryItem(name: "scope", value: scope.rawValue)]
        )
        return RecurringAmortization(monthlyExpense: Money(dto.monthlyExpense), monthlyIncome: Money(dto.monthlyIncome))
    }

    public func create(_ draft: RecurringDraft) async throws {
        try await client.send("POST", "/recurring", body: RecurringBody(draft))
    }

    /// 沒有 `account_id` 時，後端會清空關聯帳戶。
    public func update(_ id: RecurringItemID, with draft: RecurringDraft) async throws {
        try await client.send("PUT", "/recurring/\(id.rawValue)", body: RecurringBody(draft))
    }

    public func delete(_ id: RecurringItemID) async throws {
        try await client.send("DELETE", "/recurring/\(id.rawValue)")
    }

    /// token 放在 Authorization header(web 放在 URL query)。
    public func exportCSV() async throws -> Data {
        try await client.getRaw("/export/recurring")
    }
}

/// `GET /recurring` 的一筆：資料表欄位加上 JOIN 的 `account_name`、`user_name`。
private struct RecurringItemDTO: Decodable {
    let id: String
    let userID: String?
    let userName: String?
    /// 上游 ADR 0016 起的欄位(0/1);舊的回應沒有，當成個人私帳。
    let isShared: Int?
    let accountID: String?
    let accountName: String?
    let name: String
    let type: String
    let amount: Decimal
    let cycle: String
    let dayOfCycle: Int
    /// 上游 `feabed3` 起的欄位;舊的回應沒有，當成 1。
    let monthOfCycle: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, amount, cycle
        case userID = "user_id"
        case userName = "user_name"
        case isShared = "is_shared"
        case accountID = "account_id"
        case accountName = "account_name"
        case dayOfCycle = "day_of_cycle"
        case monthOfCycle = "month_of_cycle"
    }

    func item() throws -> RecurringItem {
        guard let type = TransactionType(rawValue: type), let cycle = RecurringCycle(rawValue: cycle) else {
            throw RepositoryError.unreadableResponse
        }
        return RecurringItem(
            id: RecurringItemID(id),
            name: name,
            type: type,
            amount: Money(amount),
            cycle: cycle,
            dayOfCycle: dayOfCycle,
            monthOfCycle: monthOfCycle ?? 1,
            accountID: accountID.map(AccountID.init),
            accountName: accountName,
            isShared: (isShared ?? 0) != 0,
            ownerID: userID.map(UserID.init),
            ownerName: userName
        )
    }
}

private struct AmortizationDTO: Decodable {
    let monthlyExpense: Decimal
    let monthlyIncome: Decimal

    enum CodingKeys: String, CodingKey {
        case monthlyExpense = "monthly_expense"
        case monthlyIncome = "monthly_income"
    }
}

/// `account_id` 是 `nil` 時整個欄位不送(跟 web 一樣)。
private struct RecurringBody: Encodable {
    let name: String
    let type: String
    let amount: Decimal
    let cycle: String
    let dayOfCycle: Int
    let monthOfCycle: Int
    let accountID: String?
    /// 0/1(資料表旗標);家庭公帳是 1。
    let isShared: Int

    enum CodingKeys: String, CodingKey {
        case name, type, amount, cycle
        case dayOfCycle = "day_of_cycle"
        case monthOfCycle = "month_of_cycle"
        case accountID = "account_id"
        case isShared = "is_shared"
    }

    init(_ draft: RecurringDraft) {
        name = draft.name
        type = draft.type.rawValue
        amount = draft.amount.amount
        cycle = draft.cycle.rawValue
        dayOfCycle = draft.dayOfCycle
        monthOfCycle = draft.monthOfCycle
        accountID = draft.accountID?.rawValue
        isShared = draft.isShared ? 1 : 0
    }
}
