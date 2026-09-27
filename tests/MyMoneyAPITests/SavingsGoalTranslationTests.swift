import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("儲蓄目標的翻譯(/goals)")
struct SavingsGoalTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveSavingsGoalRepository {
        LiveSavingsGoalRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try #require(request?.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    @Test("解讀儲蓄目標:deadline 可以是 null")
    func listDecodesGoals() async throws {
        try stub.reply(status: 200, fixture: "goals-list.json")

        let goals = try await repository.goals()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "goals"))
        try #require(goals.count == 3)
        #expect(goals[0] == SavingsGoal(
            id: SavingsGoalID("ace9807e-ebb5-4c86-b7e0-9939a642c5a4"),
            name: "沖繩旅遊",
            emoji: "✈️",
            targetAmount: Money(60000),
            savedAmount: Money(3000),
            monthlyReserve: Money(5000),
            deadline: CalendarDay(year: 2027, month: 3, day: 31)
        ))
        #expect(goals[1].deadline == nil)
        #expect(goals[2].isAchieved)
    }

    @Test("沒有任何儲蓄目標")
    func emptyList() async throws {
        try stub.reply(status: 200, fixture: "goals-list-empty.json")

        #expect(try await repository.goals().isEmpty)
    }

    @Test("建立時 POST /goals;有截止日時送 YYYY-MM-DD")
    func createSendsBody() async throws {
        try stub.reply(status: 201, fixture: "goals-create-trip.json")

        try await repository.create(SavingsGoalDraft(
            name: "沖繩旅遊", emoji: "✈️", targetAmount: Money(60000), monthlyReserve: Money(5000),
            deadline: CalendarDay(year: 2027, month: 3, day: 31)
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        let json = try body(request)
        #expect(json["name"] as? String == "沖繩旅遊")
        #expect(json["emoji"] as? String == "✈️")
        #expect(json["target_amount"] as? Int == 60000)
        #expect(json["monthly_reserve"] as? Int == 5000)
        #expect(json["deadline"] as? String == "2027-03-31")
    }

    @Test("編輯時 PUT /goals/:id;沒有截止日時不送 deadline(後端會清成 null)")
    func updateWithoutDeadline() async throws {
        try stub.reply(status: 200, fixture: "goals-update.json")

        try await repository.update(SavingsGoalID("0a8d69f5-9d92-4ac0-b574-16032fef5064"), with: SavingsGoalDraft(
            name: "iOS 小目標(改)", emoji: "🎨", targetAmount: Money(2000), monthlyReserve: .zero, deadline: nil
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == stub.baseURL.appending(path: "goals/0a8d69f5-9d92-4ac0-b574-16032fef5064"))
        let json = try body(request)
        #expect(json["deadline"] == nil)
        #expect(json["monthly_reserve"] as? Int == 0)
    }

    @Test("存入時 POST /goals/:id/deposit {amount}")
    func depositSendsAmount() async throws {
        try stub.reply(status: 200, fixture: "goals-deposit.json")

        try await repository.deposit(Money(3000), into: SavingsGoalID("ace9807e-ebb5-4c86-b7e0-9939a642c5a4"))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "goals/ace9807e-ebb5-4c86-b7e0-9939a642c5a4/deposit"))
        #expect(try body(request)["amount"] as? Int == 3000)
    }

    @Test("後端的錯誤原樣傳遞：缺名稱、存入 0 元、目標不存在")
    func rejections() async throws {
        let id = SavingsGoalID("0a8d69f5-9d92-4ac0-b574-16032fef5064")

        try stub.reply(status: 400, fixture: "goals-create-missing-name.json")
        await #expect(throws: RepositoryError.rejected("請填寫目標名稱和金額")) {
            try await repository.create(SavingsGoalDraft(
                name: "", emoji: "🎯", targetAmount: Money(1000), monthlyReserve: .zero, deadline: nil
            ))
        }

        try stub.reply(status: 400, fixture: "goals-deposit-invalid.json")
        await #expect(throws: RepositoryError.rejected("金額必須大於 0")) {
            try await repository.deposit(.zero, into: id)
        }

        try stub.reply(status: 404, fixture: "goals-delete-not-found.json")
        await #expect(throws: RepositoryError.rejected("目標不存在")) {
            try await repository.delete(id)
        }
    }

    @Test("刪除時 DELETE /goals/:id")
    func delete() async throws {
        try stub.reply(status: 200, fixture: "goals-delete.json")

        try await repository.delete(SavingsGoalID("0a8d69f5-9d92-4ac0-b574-16032fef5064"))

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "goals/0a8d69f5-9d92-4ac0-b574-16032fef5064"))
    }
}
