import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("現金流預測與購買力試算的翻譯(/forecast,camelCase)")
struct ForecastTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveForecastRepository {
        LiveForecastRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("30 天逐日餘額、最低餘額與日期、透支風險、預定收支")
    func forecast() async throws {
        try stub.reply(status: 200, fixture: "forecast.json")

        let forecast = try await repository.forecast(scope: .all)

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "forecast").appending(queryItems: [URLQueryItem(name: "scope", value: "all")]))
        #expect(forecast.dailyBalances.count == 30)
        #expect(forecast.dailyBalances.first == DailyBalance(date: CalendarDay(year: 2026, month: 9, day: 27), balance: Money(65440)))
        #expect(forecast.minBalance == Money(53440))
        #expect(forecast.minDate == CalendarDay(year: 2026, month: 10, day: 5))
        #expect(!forecast.willOverdraft)
        #expect(forecast.events == [
            ForecastEvent(date: CalendarDay(year: 2026, month: 10, day: 5), name: "房租", type: .expense, amount: Money(12000)),
            ForecastEvent(date: CalendarDay(year: 2026, month: 10, day: 25), name: "薪水", type: .income, amount: Money(45000)),
        ])
    }

    @Test("購買力試算:POST /forecast/purchase-check {amount}")
    func purchaseCheckSendsAmount() async throws {
        try stub.reply(status: 200, fixture: "forecast-purchase-safe.json")

        let check = try await repository.checkPurchase(Money(1000), scope: .all)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "forecast/purchase-check"))
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["amount"] as? Int == 1000)
        #expect(json["scope"] as? String == "all", "購買力試算一律明確帶 scope")
        #expect(check == PurchaseCheck(amount: Money(1000), verdict: .safe, minBalance: Money(52440), affectedGoalNames: ["沖繩旅遊"]))
    }

    @Test("評估結果：審慎評估帶上受影響的儲蓄目標，不建議購買帶上最低餘額")
    func verdicts() async throws {
        try stub.reply(status: 200, fixture: "forecast-purchase-caution.json")
        let caution = try await repository.checkPurchase(Money(50000), scope: .all)
        #expect(caution.verdict == .caution)
        #expect(caution.affectedGoalNames == ["沖繩旅遊"])

        try stub.reply(status: 200, fixture: "forecast-purchase-danger.json")
        let danger = try await repository.checkPurchase(Money(60000), scope: .all)
        #expect(danger.verdict == .danger)
        #expect(danger.minBalance == Money(-6560))
    }

    @Test("金額無效時原樣傳遞「請輸入有效金額」")
    func invalidAmount() async throws {
        try stub.reply(status: 400, fixture: "forecast-purchase-invalid.json")

        await #expect(throws: RepositoryError.rejected("請輸入有效金額")) {
            try await repository.checkPurchase(.zero, scope: .all)
        }
    }

    @Test("視角:預測一律明確帶 scope;家庭公帳視角的起始餘額與事件由後端依視角算好", arguments: [ViewScope.all, .household, .personal])
    func forecastSendsScope(scope: ViewScope) async throws {
        try stub.reply(status: 200, fixture: "forecast-scope-\(scope.rawValue).json")

        let forecast = try await repository.forecast(scope: scope)

        #expect(stub.requests.first?.url?.query() == "scope=\(scope.rawValue)")
        #expect(forecast.dailyBalances.count == 30)
        switch scope {
        case .household:
            // 測試帳號沒有加入家庭:公帳視角只有一個家庭共同帳戶的餘額、沒有預定收支;最低餘額就是起始餘額，發生在第一天。
            #expect(forecast.dailyBalances.first?.balance == Money(6900))
            #expect(forecast.events.isEmpty)
            #expect(forecast.minDate == forecast.dailyBalances.first?.date)
        case .all, .personal:
            #expect(forecast.events.contains { $0.name.hasPrefix("繳卡費 · ") }, "信用卡繳款日的繳卡費事件(上游 ADR 0017)")
        }
    }

    @Test("購買力試算帶視角:公帳視角照後端的結果,個人私帳視角帶出受影響的儲蓄目標", arguments: [ViewScope.household, .personal])
    func purchaseCheckSendsScope(scope: ViewScope) async throws {
        try stub.reply(status: 200, fixture: "forecast-purchase-scope-\(scope.rawValue).json")

        let check = try await repository.checkPurchase(Money(10000), scope: scope)

        let body = try #require(stub.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["scope"] as? String == scope.rawValue)
        #expect(json["amount"] as? Int == 10000)
        if scope == .household {
            #expect(check.verdict == .danger)
            #expect(check.minBalance == Money(-3100))
            #expect(check.affectedGoalNames.isEmpty, "公帳視角不檢核成員個人的儲蓄目標")
        } else {
            #expect(check.verdict == .safe)
            #expect(check.affectedGoalNames == ["沖繩旅遊"])
        }
    }

    @Test("預定收支帶歸屬(is_shared 0/1)與資產帳戶名稱(account_name，可能沒有);繳卡費事件是合併的一筆,名稱與金額照後端(上游 5b2faa6)")
    func eventsCarryOwnershipAndAccount() async throws {
        try stub.reply(status: 200, fixture: "forecast-scope-all.json")

        let events = try await repository.forecast(scope: .all).events

        try #require(events.count == 2)
        #expect(events[0].name == "繳卡費 · iOS 測試小額卡（已出帳）", "事件名稱照後端，client 不加工;不再有 💳")
        #expect(events[0].accountName == "iOS 測試小額卡")
        #expect(events[0].amount == Money(13000))
        #expect(events[0].key == "card_due:a1d2f913-9872-4868-88de-0e523ca46a3c:2026-10-20")
        #expect(events[0].canSettle)
        #expect(events.allSatisfy { !$0.isShared }, "測試帳號沒有家庭公帳的事件")
        #expect(events[1].accountName == nil)
    }

    @Test("起始餘額、現金總額、活存帳戶總額照後端(上游 5b2faa6);client 不加總也不扣減")
    func startingBalanceFields() async throws {
        try stub.reply(status: 200, fixture: "forecast-scope-all.json")

        let forecast = try await repository.forecast(scope: .all)

        #expect(forecast.startingBalance == Money(86570))
        #expect(forecast.cashTotal == Money(1750))
        #expect(forecast.bankTotal == Money(101200))
        #expect(forecast.dailyBalances.first?.balance == Money(86570))
    }

    @Test("舊的回應沒有起始餘額三個欄位:當成沒有,不壞掉")
    func legacyForecastHasNoStartingBalance() async throws {
        try stub.reply(status: 200, fixture: "forecast.json")

        let forecast = try await repository.forecast(scope: .all)

        #expect(forecast.startingBalance == nil)
        #expect(forecast.cashTotal == nil)
        #expect(forecast.bankTotal == nil)
    }

    @Test("舊的回應事件沒有 is_shared、account_name 時：當個人私帳、沒有帳戶，不壞掉")
    func legacyEventsAreTolerated() async throws {
        try stub.reply(status: 200, fixture: "forecast.json")

        let events = try await repository.forecast(scope: .all).events

        #expect(events.allSatisfy { !$0.isShared && $0.accountName == nil })
    }

    // MARK: 預測事件已繳(上游 ADR 0018)

    private static let rentKey = "recurring:46105044-a9d2-4e49-bf37-215361aabf32:2026-10-05"

    @Test("事件帶唯一識別碼、已繳狀態與能不能勾選;已繳的事件仍在清單裡，後端已把它從最低餘額排除")
    func eventsCarrySettlementState() async throws {
        try stub.reply(status: 200, fixture: "forecast-scope-all-settled.json")

        let forecast = try await repository.forecast(scope: .all)

        let rent = try #require(forecast.events.first { $0.name == "房租" })
        #expect(rent.key == Self.rentKey)
        #expect(rent.isSettled)
        #expect(rent.canSettle)
        let others = forecast.events.filter { $0.name != "房租" }
        try #require(others.count == 3)
        #expect(others.allSatisfy { !$0.isSettled && $0.canSettle && $0.key != nil })
        #expect(forecast.minBalance == Money(73570), "已繳的房租 12,000 不再計入:61,570 變成 73,570")
    }

    // MARK: 信用卡週期收支的現金流平移(上游 ADR 0019 第 4 點，純後端)

    private static let subscriptionKey = "recurring:194536b6-c42a-435c-ba3b-384d62239705:2026-10-18"

    /// 錄製方式:暫時建立信用卡「iOS 測試週期卡」(結帳日 8、繳款日 18)與綁定它的週期支出「iOS 測試卡訂閱」(每月 6 號 500)，
    /// 錄完刪除。6 號在結帳日 8 號之前，算進本期，扣款日從 6 號平移到繳款日 10 月 18 日。
    @Test("綁信用卡的週期收支:預測事件的日期是信用卡繳款日(不是每月 6 號)，識別碼的日期也是平移後的，名稱照後端，而且可以勾已繳")
    func creditCardRecurringEventIsShiftedToTheDueDay() async throws {
        try stub.reply(status: 200, fixture: "forecast-credit-card-recurring.json")

        let forecast = try await repository.forecast(scope: .all)

        let item = try #require(forecast.events.first { $0.name.hasPrefix("iOS 測試卡訂閱") })
        #expect(item.date == CalendarDay(year: 2026, month: 10, day: 18))
        #expect(item.name == "iOS 測試卡訂閱 (iOS 測試週期卡 · 信用卡繳款日扣款)", "事件名稱照後端，client 不加工")
        #expect(item.accountName == "iOS 測試週期卡")
        #expect(item.amount == Money(500))
        #expect(item.type == .expense)
        #expect(item.key == Self.subscriptionKey)
        #expect(item.canSettle && !item.isSettled)
        #expect(forecast.minBalance == Money(61070))
    }

    @Test("信用卡週期收支的事件勾已繳:POST 平移後的識別碼;重抓之後事件標成已繳，後端把 500 排除(最低餘額 61,070 → 61,570)")
    func creditCardRecurringEventCanBeSettled() async throws {
        try stub.reply(status: 200, fixture: "forecast-settle-credit-card-recurring.json")
        try await repository.setSettled(true, forEventKey: Self.subscriptionKey)
        let body = try #require(stub.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["event_key"] as? String == Self.subscriptionKey)
        #expect(json["settled"] as? Bool == true)

        try stub.reply(status: 200, fixture: "forecast-credit-card-recurring-settled.json")
        let forecast = try await repository.forecast(scope: .all)

        let item = try #require(forecast.events.first { $0.name.hasPrefix("iOS 測試卡訂閱") })
        #expect(item.isSettled && item.canSettle)
        #expect(forecast.minBalance == Money(61570))
    }

    @Test("舊的回應沒有 event_key、is_settled、can_settle 時:沒有識別碼、未繳、不能勾選，不壞掉")
    func legacyEventsCannotBeSettled() async throws {
        try stub.reply(status: 200, fixture: "forecast.json")

        let events = try await repository.forecast(scope: .all).events

        #expect(events.allSatisfy { $0.key == nil && !$0.isSettled && !$0.canSettle })
    }

    @Test("勾選已繳:POST /forecast/settle {event_key, settled:true}", arguments: [true, false])
    func settleSendsKeyAndFlag(settled: Bool) async throws {
        try stub.reply(status: 200, fixture: settled ? "forecast-settle-on.json" : "forecast-settle-off.json")

        try await repository.setSettled(settled, forEventKey: Self.rentKey)

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "forecast/settle"))
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["event_key"] as? String == Self.rentKey)
        #expect(json["settled"] as? Bool == settled)
    }

    @Test("後端拒絕時原樣傳遞訊息")
    func settleRejectionPassesTheMessage() async throws {
        try stub.reply(status: 400, fixture: "forecast-settle-invalid.json")

        await #expect(throws: RepositoryError.rejected("缺少 event_key")) {
            try await repository.setSettled(true, forEventKey: "")
        }
    }
}
