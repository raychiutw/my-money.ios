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

        let items = try await repository.items(scope: .all)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "recurring").appending(queryItems: [URLQueryItem(name: "scope", value: "all")]))
        try #require(items.count == 3)
        #expect(items[0] == RecurringItem(
            id: RecurringItemID("46105044-a9d2-4e49-bf37-215361aabf32"),
            name: "房租",
            type: .expense,
            amount: Money(12000),
            cycle: .monthly,
            dayOfCycle: 5,
            accountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            accountName: "iOS 測試存款",
            ownerID: UserID("ff646114-6f6b-4a37-9e27-4757868af51d")
        ))
        #expect(items[1].cycle == .annual)
        #expect(items[1].accountID == nil)
        #expect(items[2].type == .income)
    }

    @Test("讀到繳費月份(month_of_cycle):月繳與舊資料是 1，季繳可以是 2")
    func listDecodesMonthOfCycle() async throws {
        try stub.reply(status: 200, fixture: "recurring-list-with-month.json")

        let items = try await repository.items(scope: .all)

        try #require(items.count == 4)
        #expect(items.map(\.monthOfCycle) == [1, 1, 1, 2])
        #expect(items[3].cycle == .quarterly)
        #expect(items[3].name == "iOS 測試保險費")
    }

    @Test("舊的回應沒有 month_of_cycle 欄位時當成 1，不壞掉")
    func missingMonthOfCycleDefaultsToOne() async throws {
        try stub.reply(status: 200, fixture: "recurring-list.json")

        let items = try await repository.items(scope: .all)

        #expect(items.map(\.monthOfCycle) == [1, 1, 1])
    }

    @Test("新增與更新都送 month_of_cycle")
    func sendsMonthOfCycle() async throws {
        try stub.reply(status: 201, fixture: "recurring-create-quarterly.json")
        try await repository.create(RecurringDraft(
            name: "iOS 測試保險費", type: .expense, amount: Money(3000), cycle: .quarterly, dayOfCycle: 5, monthOfCycle: 2, accountID: nil
        ))
        let created = try body(stub.requests.last)
        #expect(created["month_of_cycle"] as? Int == 2)
        #expect(created["cycle"] as? String == "quarterly")

        try stub.reply(status: 200, fixture: "recurring-update-month.json")
        try await repository.update(RecurringItemID("78aa0705-cb03-402d-bbc4-b3e778f8c732"), with: RecurringDraft(
            name: "iOS 測試保險費", type: .expense, amount: Money(3000), cycle: .semiannual, dayOfCycle: 5, monthOfCycle: 4, accountID: nil
        ))
        let updated = try body(stub.requests.last)
        #expect(updated["month_of_cycle"] as? Int == 4)
        #expect(stub.requests.last?.httpMethod == "PUT")
    }

    @Test("每月平均用後端算好的每月合計")
    func amortizationDecodes() async throws {
        try stub.reply(status: 200, fixture: "recurring-amortize.json")

        let amortization = try await repository.amortization(scope: .all)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "recurring/amortize").appending(queryItems: [URLQueryItem(name: "scope", value: "all")]))
        #expect(amortization == RecurringAmortization(monthlyExpense: Money(14000), monthlyIncome: Money(45000)))
    }

    @Test("視角:列表與每月平均一律明確帶 scope(全部也帶)", arguments: [ViewScope.all, .household, .personal])
    func sendsScope(scope: ViewScope) async throws {
        try stub.reply(status: 200, fixture: "recurring-list-scope-\(scope == .all ? "all" : scope == .household ? "household" : "personal").json")
        _ = try await repository.items(scope: scope)
        try stub.reply(status: 200, fixture: "recurring-amortize-scope-\(scope == .household ? "household" : "all").json")
        _ = try await repository.amortization(scope: scope)

        #expect(stub.requests.first?.url?.query() == "scope=\(scope.rawValue)")
        #expect(stub.requests.last?.url?.query() == "scope=\(scope.rawValue)")
    }

    @Test("上游 ADR 0016 起的欄位:歸屬(is_shared 0/1)、建立者 ID 與名稱(user_id、user_name)")
    func decodesOwnershipAndOwner() async throws {
        try stub.reply(status: 200, fixture: "recurring-list-scope-all.json")

        let items = try await repository.items(scope: .all)

        try #require(items.count == 3)
        #expect(items.allSatisfy { !$0.isShared }, "測試帳號的項目都沒綁家庭共同帳戶，是個人私帳")
        #expect(items.allSatisfy { $0.ownerID == UserID("ff646114-6f6b-4a37-9e27-4757868af51d") && $0.ownerName == "iOS 測試帳號" })
    }

    @Test("舊的回應沒有 is_shared、user_id、user_name 時：當個人私帳、不知道建立者，不壞掉")
    func missingOwnershipFieldsAreTolerated() async throws {
        try stub.reply(status: 200, fixture: "recurring-list.json")

        let items = try await repository.items(scope: .all)

        #expect(items.allSatisfy { !$0.isShared && $0.ownerName == nil })
    }

    @Test("家庭公帳視角沒有項目時是空清單，每月平均是 0")
    func householdScopeCanBeEmpty() async throws {
        try stub.reply(status: 200, fixture: "recurring-list-scope-household.json")
        #expect(try await repository.items(scope: .household).isEmpty)

        try stub.reply(status: 200, fixture: "recurring-amortize-scope-household.json")
        #expect(try await repository.amortization(scope: .household) == .zero)
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

    @Test("新增與更新送 is_shared(0/1):家庭公帳 1、個人私帳 0")
    func sendsOwnership() async throws {
        try stub.reply(status: 201, fixture: "recurring-create-shared.json")
        try await repository.create(RecurringDraft(
            name: "iOS 測試網路費", type: .expense, amount: Money(899), cycle: .monthly, dayOfCycle: 12, accountID: nil, isShared: true
        ))
        #expect(try body(stub.requests.last)["is_shared"] as? Int == 1)

        try stub.reply(status: 200, fixture: "recurring-update-ownership.json")
        try await repository.update(RecurringItemID("35510e57-9131-4544-a8fa-0483316fd68a"), with: RecurringDraft(
            name: "iOS 測試網路費", type: .expense, amount: Money(899), cycle: .monthly, dayOfCycle: 12, accountID: nil, isShared: false
        ))
        #expect(try body(stub.requests.last)["is_shared"] as? Int == 0)
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
