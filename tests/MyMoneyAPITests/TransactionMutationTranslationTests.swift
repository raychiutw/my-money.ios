import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("交易紀錄的編輯、刪除與 CSV 匯出(PUT、DELETE /transactions、GET /export/csv)")
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
}
