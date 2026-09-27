import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("統計與預算的翻譯(/transactions/summary/*、/budgets)")
struct StatisticsTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")
    private let september = CalendarMonth(year: 2026, month: 9)

    private var repository: LiveStatisticsRepository {
        LiveStatisticsRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private func query(_ request: URLRequest?) throws -> [String: String] {
        let url = try #require(request?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("支出分類：帶上月份與視角，依後端的順序")
    func categoryExpenses() async throws {
        try stub.reply(status: 200, fixture: "stats-category.json")

        let expenses = try await repository.categoryExpenses(month: september, scope: .household)

        #expect(stub.requests.first?.url?.path() == "/transactions/summary/category")
        #expect(try query(stub.requests.first) == ["month": "2026-09", "scope": "household"])
        #expect(expenses == [
            CategoryExpense(category: TransactionCategory("購物"), total: Money(880)),
            CategoryExpense(category: .dining, total: Money(120)),
        ])
    }

    @Test("這個月沒有支出")
    func categoryExpensesEmpty() async throws {
        try stub.reply(status: 200, fixture: "stats-category-empty.json")

        #expect(try await repository.categoryExpenses(month: CalendarMonth(year: 2026, month: 8), scope: .all).isEmpty)
    }

    @Test("收支趨勢：帶上年份與視角，把同一個月的收入與支出合成一筆")
    func monthlySummaries() async throws {
        try stub.reply(status: 200, fixture: "stats-monthly.json")

        let summaries = try await repository.monthlySummaries(year: 2026, scope: .personal)

        #expect(stub.requests.first?.url?.path() == "/transactions/summary/monthly")
        #expect(try query(stub.requests.first) == ["year": "2026", "scope": "personal"])
        #expect(summaries == [MonthlySummary(month: september, income: Money(45000), expense: Money(1000))])
    }

    @Test("公帳代墊款：每位家庭成員一筆")
    func householdShares() async throws {
        try stub.reply(status: 200, fixture: "stats-household-shares.json")

        let shares = try await repository.householdShares(month: september)

        #expect(stub.requests.first?.url?.path() == "/transactions/summary/household-shares")
        #expect(try query(stub.requests.first) == ["month": "2026-09"])
        #expect(shares == [HouseholdShare(
            userID: UserID("ff646114-6f6b-4a37-9e27-4757868af51d"), userName: "iOS 測試帳號", total: Money(120)
        )])
    }

    @Test("沒有家庭群組時沒有公帳代墊款")
    func householdSharesWithoutHousehold() async throws {
        try stub.reply(status: 200, fixture: "stats-household-shares-empty.json")

        #expect(try await repository.householdShares(month: september).isEmpty)
    }

    @Test("分類預算：帶上已花與超支(後端算好)")
    func budgets() async throws {
        try stub.reply(status: 200, fixture: "budgets-list.json")

        let budgets = try await repository.budgets(month: september)

        #expect(stub.requests.first?.url?.path() == "/budgets")
        #expect(try query(stub.requests.first) == ["month": "2026-09"])
        #expect(budgets == [
            Budget(category: .dining, amount: Money(100), spent: Money(120), isOver: true),
            Budget(category: TransactionCategory("購物"), amount: Money(1000), spent: Money(880), isOver: false),
        ])
    }

    @Test("這個月還沒有分類預算")
    func budgetsEmpty() async throws {
        try stub.reply(status: 200, fixture: "budgets-list-empty.json")

        #expect(try await repository.budgets(month: september).isEmpty)
    }

    @Test("設定分類預算：PUT /budgets {category, amount, month}")
    func setBudget() async throws {
        try stub.reply(status: 200, fixture: "budgets-put-update.json")

        try await repository.setBudget(Money(100), for: .dining, month: september)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "/budgets")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["category"] as? String == "餐飲")
        #expect(json["amount"] as? Int == 100)
        #expect(json["month"] as? String == "2026-09")
    }

    @Test("缺少欄位時原樣傳遞「請填寫所有欄位」")
    func setBudgetRejected() async throws {
        try stub.reply(status: 400, fixture: "budgets-put-missing-amount.json")

        await #expect(throws: RepositoryError.rejected("請填寫所有欄位")) {
            try await repository.setBudget(.zero, for: .dining, month: september)
        }
    }
}
