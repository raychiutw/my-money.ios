import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("收支明細的編輯、刪除與 CSV 匯出(PUT、DELETE /transactions、GET /export/csv)")
struct TransactionMutationTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveTransactionRepository {
        LiveTransactionRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private let id = TransactionID("05495514-ef73-455b-ae60-a52456bc2a6c")

    @Test("編輯時 PUT /transactions/:id,欄位跟記一筆相同")
    func updateSendsBody() async throws {
        try stub.reply(status: 200, fixture: "transactions-update.json")

        try await repository.update(id, with: TransactionDraft(
            accountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            type: .expense,
            category: TransactionCategory("交通"),
            amount: Money(75),
            note: "計程車",
            date: CalendarDay(year: 2026, month: 9, day: 26),
            isShared: false
        ))

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == stub.baseURL.appending(path: "transactions/05495514-ef73-455b-ae60-a52456bc2a6c"))
        let data = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["amount"] as? Int == 75)
        #expect(json["is_shared"] as? Int == 0)
        #expect(json["note"] as? String == "計程車")
    }

    @Test("刪除時 DELETE /transactions/:id")
    func deleteSucceeds() async throws {
        try stub.reply(status: 200, fixture: "transactions-delete.json")

        try await repository.delete(id)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url == stub.baseURL.appending(path: "transactions/05495514-ef73-455b-ae60-a52456bc2a6c"))
    }

    @Test("刪除不存在的紀錄時，原樣傳遞「紀錄不存在」")
    func deleteNotFound() async throws {
        try stub.reply(status: 404, fixture: "transactions-delete-not-found.json")

        await #expect(throws: RepositoryError.rejected("紀錄不存在")) {
            try await repository.delete(id)
        }
    }

    /// web 把 JWT 放在 URL query 裡(會留在瀏覽紀錄和伺服器 log);iOS 改用 header(parity 刻意偏離第 18 項)。
    @Test("匯出 CSV 時 token 放在 Authorization header,不放進 URL")
    func exportUsesAuthorizationHeader() async throws {
        try stub.reply(status: 200, fixture: "export-transactions.csv")

        _ = try await repository.exportCSV(
            from: CalendarDay(year: 2026, month: 9, day: 1), to: CalendarDay(year: 2026, month: 9, day: 30)
        )

        let request = try #require(stub.requests.first)
        let url = try #require(request.url)
        #expect(url.path() == "/export/csv")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(items.map(\.name)) == ["from", "to"])
        #expect(items.first { $0.name == "from" }?.value == "2026-09-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    }

    @Test("匯出的 CSV 原樣回傳(含 BOM,不是 JSON envelope)")
    func exportReturnsRawCSV() async throws {
        try stub.reply(status: 200, fixture: "export-transactions.csv")

        let data = try await repository.exportCSV(
            from: CalendarDay(year: 2026, month: 9, day: 1), to: CalendarDay(year: 2026, month: 9, day: 30)
        )

        #expect(data == (try Fixture.data("export-transactions.csv")))
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test("匯出時 token 失效是 session 過期")
    func exportExpiredSession() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-token.json")

        await #expect(throws: RepositoryError.sessionExpired) {
            try await repository.exportCSV(
                from: CalendarDay(year: 2026, month: 9, day: 1), to: CalendarDay(year: 2026, month: 9, day: 30)
            )
        }
    }

    // MARK: 信用卡的帳單狀態與延至下期(上游 ADR 0020，#184)

    private let card = AccountID("a1d2f913-9872-4868-88de-0e523ca46a3c")

    @Test("記一筆與編輯都送 defer_to_next_statement(0/1，跟 web 一樣);建立回應 201", arguments: [true, false])
    func bodiesCarryTheDeferFlag(defers: Bool) async throws {
        try stub.reply(status: 201, fixture: "transactions-create-deferred.json")
        let draft = TransactionDraft(
            accountID: card, type: .expense, category: TransactionCategory("餐飲"), amount: Money(321), note: "延至下期測試",
            date: CalendarDay(year: 2026, month: 10, day: 4), isShared: false, defersToNextStatement: defers
        )

        try await repository.create(draft)
        try stub.reply(status: 200, fixture: "transactions-update.json")
        try await repository.update(id, with: draft)

        for request in stub.requests {
            let body = try #require(request.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["defer_to_next_statement"] as? Int == (defers ? 1 : 0), "\(request.httpMethod ?? "")")
        }
        #expect(stub.requests.count == 2)
    }

    @Test("列表解讀帳單狀態:已出帳、延至下期(未出帳而且延期)、其他是未出帳;舊的回應沒有欄位也是未出帳")
    func listDecodesBillingStatus() async throws {
        try stub.reply(status: 200, fixture: "transactions-card-billing-state.json")

        let cardTransactions = try await repository.transactions(
            from: nil, to: nil, scope: .all, accountID: card, limit: 200, offset: 0
        )

        #expect(cardTransactions.first { $0.note == "延至下期測試" }?.billing == .deferred)
        #expect(cardTransactions.first { $0.note == "出帳狀態測試" }?.billing == .billed)

        try stub.reply(status: 200, fixture: "transactions-list.json")
        let legacy = try await repository.transactions(from: nil, to: nil, scope: .all, limit: 200, offset: 0)
        #expect(legacy.allSatisfy { $0.billing == .unbilled })
    }
}
