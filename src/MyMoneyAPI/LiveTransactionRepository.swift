import Foundation
import MyMoneyDomain

/// `/transactions` 的 URLSession 實作。
public struct LiveTransactionRepository: TransactionRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, accountID: AccountID?, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        // 起日或迄日是 nil 時整個參數不送，後端就不限日期。
        let dates = [("from", from), ("to", to)].compactMap { name, day in day.map { URLQueryItem(name: name, value: $0.iso) } }
        // 不指定帳戶時整個參數不送(上游 ADR 0019 的 `account_id`)。
        let account = accountID.map { [URLQueryItem(name: "account_id", value: $0.rawValue)] } ?? []
        let dtos: [TransactionDTO] = try await client.get("/transactions", query: dates + account + [
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try dtos.map { try $0.transaction() }
    }

    public func page(_ query: TransactionQuery, cursor: String?, limit: Int) async throws -> TransactionPage {
        var items = Self.filterItems(query)
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        // 游標原樣帶回:後端回的 `next_cursor` 已是編碼過的字串,後端收到時會解碼。
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        // `next_cursor` 在 envelope 的最外層(跟 `data` 同層),所以自己解整個回應。
        let data = try await client.getRaw("/transactions", query: items)
        let envelope: PageEnvelope
        do {
            envelope = try JSONDecoder().decode(PageEnvelope.self, from: data)
        } catch {
            throw RepositoryError.unreadableResponse
        }
        return TransactionPage(transactions: try envelope.data.map { try $0.transaction() }, nextCursor: envelope.nextCursor)
    }

    public func rangeSummary(_ query: TransactionQuery) async throws -> RangeSummary {
        let dto: RangeSummaryDTO = try await client.get("/transactions/summary/range", query: Self.filterItems(query))
        return RangeSummary(
            totalIncome: Money(dto.totalIncome), totalExpense: Money(dto.totalExpense), count: dto.count,
            byDay: try dto.byDay.map { day in
                guard let date = CalendarDay(iso: day.date) else { throw RepositoryError.unreadableResponse }
                return RangeSummary.Day(date: date, income: Money(day.income), expense: Money(day.expense))
            }
        )
    }

    /// 篩選條件轉成查詢參數:沒有的整個不送;關鍵字去前後空白、空白不送(`GET /transactions` 與 `summary/range` 共用)。
    private static func filterItems(_ query: TransactionQuery) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "scope", value: query.scope.rawValue)]
        if let from = query.from { items.append(URLQueryItem(name: "from", value: from.iso)) }
        if let to = query.to { items.append(URLQueryItem(name: "to", value: to.iso)) }
        if let account = query.accountID { items.append(URLQueryItem(name: "account_id", value: account.rawValue)) }
        if let category = query.category { items.append(URLQueryItem(name: "category", value: category.name)) }
        if let type = query.type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        if let keyword = query.keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            items.append(URLQueryItem(name: "q", value: keyword))
        }
        return items
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

/// `GET /transactions` 的 envelope:`{success, data, next_cursor}`。
private struct PageEnvelope: Decodable {
    let data: [TransactionDTO]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

/// `GET /transactions/summary/range` 的 data(snake_case)。
private struct RangeSummaryDTO: Decodable {
    struct Day: Decodable {
        let date: String
        let income: Decimal
        let expense: Decimal
    }

    let totalIncome: Decimal
    let totalExpense: Decimal
    let count: Int
    let byDay: [Day]

    enum CodingKeys: String, CodingKey {
        case count
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case byDay = "by_day"
    }
}

/// `GET /transactions` 的一筆:資料表欄位加上 JOIN 的 `account_name`、`user_name`。
private struct TransactionDTO: Decodable {
    let id: String
    /// 記帳人的 ID。
    let userID: String?
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
    /// 上游 ADR 0020 起的欄位(0/1);舊的回應沒有，當成未出帳。
    let isBilled: Int?
    let defersToNextStatement: Int?
    /// 後端自動記下的建立時間(UTC,`YYYY-MM-DD HH:mm:ss`,#207)。
    let createdAt: String?
    /// 上游 `b06d17c` 起的欄位(UTC,同 `created_at` 格式);新建與沒改過是 null,舊的回應沒有。
    let updatedAt: String?
    /// 上游 `d0424df` 起的欄位:扣款帳戶是不是家庭共同帳戶(0/1)與報銷關聯;舊的回應沒有。
    let accountIsJoint: Int?
    let reimbursementID: String?

    enum CodingKeys: String, CodingKey {
        case id, type, category, amount, note, date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case accountIsJoint = "account_is_joint"
        case reimbursementID = "reimbursement_id"
        case accountID = "account_id"
        case accountName = "account_name"
        case isShared = "is_shared"
        case userName = "user_name"
        case userID = "user_id"
        case isBilled = "is_billed"
        case defersToNextStatement = "defer_to_next_statement"
    }

    /// 公帳的三態:共同帳戶直接扣款，否則看有沒有報銷關聯(web 的判斷順序);私帳與舊的回應(沒有 `account_is_joint`)沒有狀態。
    private var householdPayment: HouseholdPayment? {
        guard isShared == 1, let accountIsJoint else { return nil }
        if accountIsJoint == 1 { return .jointFund }
        return ReimbursementMarker(reimbursementID).payment
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
            recorderName: userName,
            recorderID: userID.map(UserID.init),
            billing: BillingStatus(isBilled: (isBilled ?? 0) != 0, defersToNextStatement: (defersToNextStatement ?? 0) != 0),
            recordedAt: RecordedTime.date(fromBackend: createdAt),
            householdPayment: householdPayment,
            updatedAt: RecordedTime.date(fromBackend: updatedAt)
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
    /// 0/1，跟 web 一樣;非信用卡一律 0。
    let defersToNextStatement: Int

    enum CodingKeys: String, CodingKey {
        case type, category, amount, note, date
        case accountID = "account_id"
        case isShared = "is_shared"
        case defersToNextStatement = "defer_to_next_statement"
    }

    init(_ draft: TransactionDraft) {
        accountID = draft.accountID.rawValue
        type = draft.type.rawValue
        category = draft.category.name
        amount = draft.amount.amount
        note = draft.note
        date = draft.date.iso
        isShared = draft.isShared ? 1 : 0
        defersToNextStatement = draft.defersToNextStatement ? 1 : 0
    }
}
