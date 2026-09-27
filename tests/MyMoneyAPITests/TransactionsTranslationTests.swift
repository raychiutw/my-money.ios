import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("交易紀錄的翻譯(GET、POST /transactions)")
struct TransactionsTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveTransactionRepository {
        LiveTransactionRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private let september1 = CalendarDay(year: 2026, month: 9, day: 1)
    private let september30 = CalendarDay(year: 2026, month: 9, day: 30)

    @Test("查詢時帶上起迄日、視角與分頁參數")
    func listSendsQuery() async throws {
        try stub.reply(status: 200, fixture: "transactions-list.json")

        _ = try await repository.transactions(from: september1, to: september30, scope: .household, limit: 200, offset: 400)

        let url = try #require(stub.requests.first?.url)
        #expect(url.path() == "/transactions")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) == [
            "from": "2026-09-01", "to": "2026-09-30", "scope": "household", "limit": "200", "offset": "400",
        ])
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    }

    @Test("解讀成交易紀錄:is_shared 0/1 是個人私帳與家庭公帳，帶上帳戶名稱與記帳人")
    func listDecodesTransactions() async throws {
        try stub.reply(status: 200, fixture: "transactions-list.json")

        let transactions = try await repository.transactions(from: september1, to: september30, scope: .all, limit: 200, offset: 0)

        try #require(transactions.count == 3)
        #expect(transactions[0] == Transaction(
            id: TransactionID("24ba06af-6565-4dc9-8960-95727636eb38"),
            accountID: AccountID("70b75089-3652-40a3-8c47-c23d04aab28c"),
            accountName: "iOS 測試信用卡",
            type: .expense,
            category: TransactionCategory("購物"),
            amount: Money(880),
            note: "耳機",
            date: CalendarDay(year: 2026, month: 9, day: 27),
            isShared: false,
            recorderName: "iOS 測試帳號"
        ))
        #expect(transactions[1].isShared)
        #expect(transactions[2].type == .income)
        #expect(transactions[2].category == .salary)
    }

    @Test("記一筆時 POST /transactions,家庭公帳送成 is_shared: 1")
    func createSendsBody() async throws {
        try stub.reply(status: 201, fixture: "transactions-create-shared-expense.json")

        try await repository.create(TransactionDraft(
            accountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            type: .expense,
            category: .dining,
            amount: Money(120),
            note: "午餐",
            date: CalendarDay(year: 2026, month: 9, day: 27),
            isShared: true
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "transactions"))
        let data = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["account_id"] as? String == "f4d3074a-4df6-4c98-bd90-bc6f2af91a37")
        #expect(json["type"] as? String == "expense")
        #expect(json["category"] as? String == "餐飲")
        #expect(json["amount"] as? Int == 120)
        #expect(json["note"] as? String == "午餐")
        #expect(json["date"] as? String == "2026-09-27")
        #expect(json["is_shared"] as? Int == 1)
    }

    @Test("欄位不齊時原樣傳遞後端的訊息")
    func createFailurePassesMessage() async throws {
        try stub.reply(status: 400, fixture: "transactions-create-missing-fields.json")

        await #expect(throws: RepositoryError.rejected("請填寫必填欄位")) {
            try await repository.create(TransactionDraft(
                accountID: AccountID(""), type: .expense, category: .dining, amount: Money(120), note: "",
                date: CalendarDay(year: 2026, month: 9, day: 27), isShared: true
            ))
        }
    }
}
