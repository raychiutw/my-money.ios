import Foundation
import MyMoneyDomain

/// `/goals` 的 URLSession 實作。
public struct LiveSavingsGoalRepository: SavingsGoalRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func goals() async throws -> [SavingsGoal] {
        let dtos: [SavingsGoalDTO] = try await client.get("/goals")
        return try dtos.map { try $0.goal() }
    }

    public func create(_ draft: SavingsGoalDraft) async throws {
        try await client.send("POST", "/goals", body: SavingsGoalBody(draft))
    }

    /// 沒有 `deadline` 時，後端會把截止日清成 `null`。
    public func update(_ id: SavingsGoalID, with draft: SavingsGoalDraft) async throws {
        try await client.send("PUT", "/goals/\(id.rawValue)", body: SavingsGoalBody(draft))
    }

    public func deposit(_ amount: Money, into id: SavingsGoalID) async throws {
        try await client.send("POST", "/goals/\(id.rawValue)/deposit", body: ["amount": amount.amount])
    }

    public func delete(_ id: SavingsGoalID) async throws {
        try await client.send("DELETE", "/goals/\(id.rawValue)")
    }
}

/// `GET /goals` 的一筆。
private struct SavingsGoalDTO: Decodable {
    let id: String
    let name: String
    let emoji: String?
    let targetAmount: Decimal
    let savedAmount: Decimal
    let monthlyReserve: Decimal?
    let deadline: String?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, deadline
        case targetAmount = "target_amount"
        case savedAmount = "saved_amount"
        case monthlyReserve = "monthly_reserve"
    }

    func goal() throws -> SavingsGoal {
        var day: CalendarDay?
        if let deadline {
            guard let parsed = CalendarDay(iso: deadline) else { throw RepositoryError.unreadableResponse }
            day = parsed
        }
        return SavingsGoal(
            id: SavingsGoalID(id),
            name: name,
            icon: SavingsGoalIcon(wire: emoji),
            targetAmount: Money(targetAmount),
            savedAmount: Money(savedAmount),
            monthlyReserve: Money(monthlyReserve ?? 0),
            deadline: day
        )
    }
}

/// `deadline` 是 `nil` 時整個欄位不送(跟 web 一樣)。
private struct SavingsGoalBody: Encodable {
    let name: String
    /// 欄位叫 `emoji`,上游 efd5064 起存的是圖示代號。
    let emoji: String
    let targetAmount: Decimal
    let monthlyReserve: Decimal
    let deadline: String?

    enum CodingKeys: String, CodingKey {
        case name, emoji, deadline
        case targetAmount = "target_amount"
        case monthlyReserve = "monthly_reserve"
    }

    init(_ draft: SavingsGoalDraft) {
        name = draft.name
        emoji = draft.icon.rawValue
        targetAmount = draft.targetAmount.amount
        monthlyReserve = draft.monthlyReserve.amount
        deadline = draft.deadline?.iso
    }
}
