import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("週期收支的翻譯(/recurring、/recurring/amortize、/export/recurring)")
struct RecurringTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveRecurringRepository {
        LiveRecurringRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try #require(request?.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    @Test("解讀週期收支:account_id 可以是 null,帶上帳戶名稱")
    func listDecodesItems() async throws {
        try stub.reply(status: 200, fixture: "recurring-list.json")

        let items = try await repository.items()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "recurring"))
        try #require(items.count == 3)
        #expect(items[0] == RecurringItem(
            id: RecurringItemID("46105044-a9d2-4e49-bf37-215361aabf32"),
            name: "房租",
            type: .expense,
            amount: Money(12000),
            cycle: .monthly,
            dayOfCycle: 5,
            accountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            accountName: "iOS 測試存款"
        ))
        #expect(items[1].cycle == .annual)
        #expect(items[1].accountID == nil)
        #expect(items[2].type == .income)
    }

    @Test("分攤平滑用後端算好的每月合計")
    func amortizationDecodes() async throws {
        try stub.reply(status: 200, fixture: "recurring-amortize.json")

        let amortization = try await repository.amortization()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "recurring/amortize"))
        #expect(amortization == RecurringAmortization(monthlyExpense: Money(14000), monthlyIncome: Money(45000)))
    }

    @Test("新增時 POST /recurring;沒有關聯帳戶時不送 account_id")
    func createSendsBody() async throws {
        try stub.reply(status: 201, fixture: "recurring-create-insurance.json")

        try await repository.create(RecurringDraft(
            name: "年繳保費", type: .expense, amount: Money(24000), cycle: .annual, dayOfCycle: 15, accountID: nil
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        let json = try body(request)
        #expect(json["name"] as? String == "年繳保費")
        #expect(json["type"] as? String == "expense")
        #expect(json["amount"] as? Int == 24000)
        #expect(json["cycle"] as? String == "annual")
        #expect(json["day_of_cycle"] as? Int == 15)
        #expect(json["account_id"] == nil)
    }

    @Test("編輯時 PUT /recurring/:id")
    func updateSendsBody() async throws {
        try stub.reply(status: 200, fixture: "recurring-update.json")

        try await repository.update(RecurringItemID("f7fb035d-f44b-4dc8-9e31-e21113e4f1a2"), with: RecurringDraft(
            name: "暫時項目(改)", type: .expense, amount: Money(360), cycle: .semiannual, dayOfCycle: 20,
            accountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37")
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == stub.baseURL.appending(path: "recurring/f7fb035d-f44b-4dc8-9e31-e21113e4f1a2"))
        #expect(try body(request)["account_id"] as? String == "f4d3074a-4df6-4c98-bd90-bc6f2af91a37")
    }

    @Test("刪除時 DELETE /recurring/:id;不存在時原樣傳遞「項目不存在」")
    func delete() async throws {
        try stub.reply(status: 200, fixture: "recurring-delete.json")
        try await repository.delete(RecurringItemID("f7fb035d-f44b-4dc8-9e31-e21113e4f1a2"))
        #expect(stub.requests.first?.httpMethod == "DELETE")

        try stub.reply(status: 404, fixture: "recurring-delete-not-found.json")
        await #expect(throws: RepositoryError.rejected("項目不存在")) {
            try await repository.delete(RecurringItemID("f7fb035d-f44b-4dc8-9e31-e21113e4f1a2"))
        }
    }

    @Test("缺少名稱時原樣傳遞「請填寫所有必填欄位」")
    func createMissingName() async throws {
        try stub.reply(status: 400, fixture: "recurring-create-missing-name.json")

        await #expect(throws: RepositoryError.rejected("請填寫所有必填欄位")) {
            try await repository.create(RecurringDraft(
                name: "", type: .expense, amount: Money(100), cycle: .monthly, dayOfCycle: 1, accountID: nil
            ))
        }
    }

    @Test("匯出週期收支 CSV:GET /export/recurring,原樣回傳")
    func exportCSV() async throws {
        try stub.reply(status: 200, fixture: "export-recurring.csv")

        let data = try await repository.exportCSV()

        #expect(stub.requests.first?.url?.path() == "/export/recurring")
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
        #expect(data == (try Fixture.data("export-recurring.csv")))
    }
}
