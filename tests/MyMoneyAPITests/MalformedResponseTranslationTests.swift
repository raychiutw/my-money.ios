import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 後端回了看不懂的欄位時，翻譯層一律丟 `unreadableResponse`(#231、#232):日期、月份、時間格式錯，或列舉值不認得。
/// 做法:取真實 fixture，在測試裡只破壞一個欄位(先確認要破壞的片段真的在 fixture 裡，免得測試空轉通過)。
@Suite("看不懂的欄位")
struct MalformedResponseTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "current-session-token")

    private var client: APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session)
    }

    /// 回覆某個 fixture，但把第 `occurrence` 個(或全部)`original` 換成 `corrupted`。
    private func reply(_ fixture: String, replacing original: String, with corrupted: String, all: Bool = false, occurrence: Int = 1) throws {
        var text = try #require(String(data: Fixture.data(fixture), encoding: .utf8))
        let ranges = text.ranges(of: original)
        try #require(ranges.count >= occurrence, "fixture \(fixture) 裡找不到第 \(occurrence) 個 \(original)")
        if all {
            text = text.replacingOccurrences(of: original, with: corrupted)
        } else {
            text.replaceSubrange(ranges[occurrence - 1], with: corrupted)
        }
        stub.reply(status: 200, json: Data(text.utf8))
    }

    // MARK: 日期、月份、時間(#231)

    @Test("收支明細的日期格式錯")
    func transactionDate() async throws {
        try reply("transactions-list.json", replacing: "\"date\":\"2026-09-27\"", with: "\"date\":\"27/09/2026\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveTransactionRepository(client: client).transactions(
                from: nil, to: nil, scope: .all, accountID: nil, limit: 50, offset: 0
            )
        }
    }

    @Test("每月統計的月份格式錯")
    func monthlyMonth() async throws {
        try reply("stats-monthly.json", replacing: "\"month\":\"2026-09\"", with: "\"month\":\"09-2026\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveStatisticsRepository(client: client).monthlySummaries(year: 2026, scope: .all)
        }
    }

    @Test("儲蓄目標的截止日格式錯;null 仍然可以")
    func goalDeadline() async throws {
        try reply("goals-list.json", replacing: "\"deadline\":\"2027-03-31\"", with: "\"deadline\":\"年底\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveSavingsGoalRepository(client: client).goals()
        }

        stub.reply(status: 200, json: try Fixture.data("goals-list.json"))
        let goals = try await LiveSavingsGoalRepository(client: client).goals()
        #expect(goals.contains { $0.deadline == nil })
    }

    @Test("預測的每日餘額日期格式錯")
    func forecastDailyDate() async throws {
        try reply("forecast.json", replacing: "\"date\":\"2026-09-27\"", with: "\"date\":\"今天\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveForecastRepository(client: client).forecast(scope: .all)
        }
    }

    @Test("家庭代墊明細的日期格式錯")
    func advanceItemDate() async throws {
        try reply("households-advances-with-time.json", replacing: "\"date\": \"2026-09-28\"", with: "\"date\": \"昨天\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveHouseholdRepository(client: client).advances()
        }
    }

    @Test("家庭報銷明細的日期格式錯")
    func reimbursementItemDate() async throws {
        try reply("households-advances-with-time.json", replacing: "\"date\": \"2026-09-28\"", with: "\"date\": \"昨天\"", occurrence: 2)
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveHouseholdRepository(client: client).advances()
        }
    }

    @Test("邀請碼到期時間格式錯")
    func invitationExpiry() async throws {
        try reply("households-invite.json", replacing: "\"expires_at\":\"2026-10-04T21:20:25.335Z\"", with: "\"expires_at\":\"明天\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveHouseholdRepository(client: client).invite()
        }
    }

    @Test("家庭成員加入時間格式錯")
    func memberJoinedAt() async throws {
        try reply("households-current.json", replacing: "\"joined_at\":\"2026-09-27 21:20:20\"", with: "\"joined_at\":\"上週\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            _ = try await LiveHouseholdRepository(client: client).current()
        }
    }

    // MARK: 不認得的列舉值(#232)

    @Test("預測事件的收支類型不認得")
    func forecastEventType() async throws {
        try reply("forecast.json", replacing: "\"type\":\"expense\"", with: "\"type\":\"refund\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveForecastRepository(client: client).forecast(scope: .all)
        }
    }

    @Test("購買力試算的判定不認得")
    func purchaseVerdict() async throws {
        try reply("forecast-purchase-safe.json", replacing: "\"verdict\":\"safe\"", with: "\"verdict\":\"maybe\"")
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveForecastRepository(client: client).checkPurchase(Money(100), scope: .all)
        }
    }

    @Test("機器人綁定的平台不認得")
    func botPlatform() async throws {
        try reply("bot-bindings.json", replacing: "\"platform\":\"line\"", with: "\"platform\":\"icq\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            _ = try await LiveBotRepository(client: client).bindings()
        }
    }

    @Test("家庭成員的角色不認得")
    func householdRole() async throws {
        try reply("households-current.json", replacing: "\"role\":\"admin\"", with: "\"role\":\"owner\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            _ = try await LiveHouseholdRepository(client: client).current()
        }
    }

    @Test("週期收支的收支類型不認得")
    func recurringType() async throws {
        try reply("recurring-list.json", replacing: "\"type\":\"expense\"", with: "\"type\":\"gift\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            _ = try await LiveRecurringRepository(client: client).items(scope: .all)
        }
    }

    @Test("週期收支的週期不認得")
    func recurringCycle() async throws {
        try reply("recurring-list.json", replacing: "\"cycle\":\"monthly\"", with: "\"cycle\":\"weekly\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            _ = try await LiveRecurringRepository(client: client).items(scope: .all)
        }
    }

    @Test("收支類型不認得(收支明細、每月統計)")
    func transactionAndMonthlyType() async throws {
        try reply("transactions-list.json", replacing: "\"type\":\"expense\"", with: "\"type\":\"refund\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveTransactionRepository(client: client).transactions(
                from: nil, to: nil, scope: .all, accountID: nil, limit: 50, offset: 0
            )
        }
        try reply("stats-monthly.json", replacing: "\"type\":\"expense\"", with: "\"type\":\"refund\"", all: true)
        await #expect(throws: RepositoryError.unreadableResponse) {
            try await LiveStatisticsRepository(client: client).monthlySummaries(year: 2026, scope: .all)
        }
    }

    // MARK: 刻意的寬鬆行為(#232)

    @Test("預測的 minDate 是空字串或壞值:當作沒有，不丟錯(上游 e138bd9 之前是空字串)")
    func minDateIsLenient() async throws {
        for corrupted in ["\"minDate\":\"\"", "\"minDate\":\"later\""] {
            try reply("forecast.json", replacing: "\"minDate\":\"2026-10-05\"", with: corrupted)
            let forecast = try await LiveForecastRepository(client: client).forecast(scope: .all)
            #expect(forecast.minDate == nil)
        }
        stub.reply(status: 200, json: try Fixture.data("forecast.json"))
        #expect(try await LiveForecastRepository(client: client).forecast(scope: .all).minDate == CalendarDay(year: 2026, month: 10, day: 5))
    }

    @Test("記帳時間 created_at 壞值:該筆沒有時間，其餘照常，不丟錯")
    func createdAtIsLenient() async throws {
        try reply("transactions-list.json", replacing: "\"created_at\":\"2026-09-27 19:57:02\"", with: "\"created_at\":\"昨天\"")
        let list = try await LiveTransactionRepository(client: client).transactions(
            from: nil, to: nil, scope: .all, accountID: nil, limit: 50, offset: 0
        )
        #expect(list.contains { $0.recordedAt == nil })
        #expect(list.contains { $0.recordedAt != nil })
    }
}
