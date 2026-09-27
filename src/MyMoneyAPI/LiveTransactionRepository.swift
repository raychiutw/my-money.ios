import Foundation
import MyMoneyDomain

/// `/transactions` 的 URLSession 實作。
public struct LiveTransactionRepository: TransactionRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func transactions(
        from: CalendarDay, to: CalendarDay, scope: ViewScope, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        let dtos: [TransactionDTO] = try await client.get("/transactions", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try dtos.map { try $0.transaction() }
    }

    public func create(_ draft: TransactionDraft) async throws {
        try await client.send("POST", "/transactions", body: TransactionBody(draft))
    }

    public func update(_ id: TransactionID, with draft: TransactionDraft) async throws {
        try await client.send("PUT", "/transactions/\(id.rawValue)", body: TransactionBody(draft))
    }

    public func delete(_ id: TransactionID) async throws {
        try await client.send("DELETE", "/transactions/\(id.rawValue)")
    }

    /// token 放在 Authorization header(web 放在 URL query,會留在瀏覽紀錄與伺服器 log)。
    public func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data {
        try await client.getRaw("/export/csv", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }
}

/// `GET /transactions` 的一筆:資料表欄位加上 JOIN 的 `account_name`、`user_name`。
private struct TransactionDTO: Decodable {
    let id: String
    let accountID: String
    let accountName: String?
    let type: String
    let category: String
    let amount: Decimal
    let note: String?
    let date: String
    /// 0/1:1 是家庭公帳，0 是個人私帳。
    let isShared: Int
    let userName: String?

    enum CodingKeys: String, CodingKey {
        case id, type, category, amount, note, date
        case accountID = "account_id"
        case accountName = "account_name"
        case isShared = "is_shared"
        case userName = "user_name"
    }

    func transaction() throws -> Transaction {
        guard let type = TransactionType(rawValue: type), let day = CalendarDay(iso: date) else {
            throw RepositoryError.unreadableResponse
        }
        return Transaction(
            id: TransactionID(id),
            accountID: AccountID(accountID),
            accountName: accountName,
            type: type,
            category: TransactionCategory(category),
            amount: Money(amount),
            note: note ?? "",
            date: day,
            isShared: isShared == 1,
            recorderName: userName
        )
    }
}

private struct TransactionBody: Encodable {
    let accountID: String
    let type: String
    let category: String
    let amount: Decimal
    let note: String
    let date: String
    let isShared: Int

    enum CodingKeys: String, CodingKey {
        case type, category, amount, note, date
        case accountID = "account_id"
        case isShared = "is_shared"
    }

    init(_ draft: TransactionDraft) {
        accountID = draft.accountID.rawValue
        type = draft.type.rawValue
        category = draft.category.name
        amount = draft.amount.amount
        note = draft.note
        date = draft.date.iso
        isShared = draft.isShared ? 1 : 0
    }
}
