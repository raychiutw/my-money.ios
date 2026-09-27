import Foundation
import MyMoneyDomain

/// `/transactions/summary/*` 與 `/budgets` 的 URLSession 實作。
public struct LiveStatisticsRepository: StatisticsRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func categoryExpenses(month: CalendarMonth, scope: ViewScope) async throws -> [CategoryExpense] {
        let rows: [CategoryRow] = try await client.get("/transactions/summary/category", query: [
            URLQueryItem(name: "month", value: month.iso),
            URLQueryItem(name: "scope", value: scope.rawValue),
        ])
        return rows.map { CategoryExpense(category: TransactionCategory($0.category), total: Money($0.total)) }
    }

    /// 後端每個月的收入與支出各一列，這裡合成一筆;沒有的那一邊是 0。
    public func monthlySummaries(year: Int, scope: ViewScope) async throws -> [MonthlySummary] {
        let rows: [MonthlyRow] = try await client.get("/transactions/summary/monthly", query: [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "scope", value: scope.rawValue),
        ])
        var byMonth: [CalendarMonth: (income: Decimal, expense: Decimal)] = [:]
        for row in rows {
            guard let month = CalendarMonth(iso: row.month), let type = TransactionType(rawValue: row.type) else {
                throw RepositoryError.unreadableResponse
            }
            switch type {
            case .income: byMonth[month, default: (0, 0)].income = row.total
            case .expense: byMonth[month, default: (0, 0)].expense = row.total
            }
        }
        return byMonth.sorted { $0.key < $1.key }.map {
            MonthlySummary(month: $0.key, income: Money($0.value.income), expense: Money($0.value.expense))
        }
    }

    public func householdShares(month: CalendarMonth) async throws -> [HouseholdShare] {
        let rows: [ShareRow] = try await client.get("/transactions/summary/household-shares", query: [
            URLQueryItem(name: "month", value: month.iso),
        ])
        return rows.map { HouseholdShare(userID: UserID($0.userID), userName: $0.userName, total: Money($0.total)) }
    }

    public func budgets(month: CalendarMonth) async throws -> [Budget] {
        let rows: [BudgetRow] = try await client.get("/budgets", query: [URLQueryItem(name: "month", value: month.iso)])
        return rows.map {
            Budget(category: TransactionCategory($0.category), amount: Money($0.amount), spent: Money($0.spent), isOver: $0.over)
        }
    }

    public func setBudget(_ amount: Money, for category: TransactionCategory, month: CalendarMonth) async throws {
        try await client.send("PUT", "/budgets", body: BudgetBody(category: category.name, amount: amount.amount, month: month.iso))
    }
}

private struct CategoryRow: Decodable {
    let category: String
    let total: Decimal
}

private struct MonthlyRow: Decodable {
    let month: String
    let type: String
    let total: Decimal
}

private struct ShareRow: Decodable {
    let userID: String
    let userName: String
    let total: Decimal

    enum CodingKeys: String, CodingKey {
        case total
        case userID = "user_id"
        case userName = "user_name"
    }
}

private struct BudgetRow: Decodable {
    let category: String
    let amount: Decimal
    let spent: Decimal
    let over: Bool
}

private struct BudgetBody: Encodable {
    let category: String
    let amount: Decimal
    let month: String
}
