import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("現金流預測與購買力試算")
struct ForecastTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func loaded(_ repository: InMemoryForecastRepository? = nil) async -> (ForecastModel, InMemoryForecastRepository) {
        let repository = repository ?? InMemoryForecastRepository.sample(today: today)
        let model = ForecastModel(repository: repository, dataVersion: DataVersion())
        await model.load()
        return (model, repository)
    }

    private func forecast(overdraft: Bool, minDate: CalendarDay?) -> CashFlowForecast {
        CashFlowForecast(
            dailyBalances: [DailyBalance(date: today, balance: Money(100))],
            minBalance: overdraft ? Money(-500) : Money(100),
            minDate: minDate,
            willOverdraft: overdraft,
            events: []
        )
    }

    @Test("資料回來之前沒有預測(畫面不會先顯示「安全」或 $0)")
    func nothingBeforeLoading() {
        let model = ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion())

        #expect(model.phase == .loading)
        #expect(model.forecast == nil)
    }

    @Test("載入失敗時也沒有預測")
    func nothingAfterFailure() async {
        let repository = InMemoryForecastRepository.sample(today: today)
        await repository.fail(with: .rejected("伺服器錯誤"))

        let (model, _) = await loaded(repository)

        #expect(model.phase == .failed("伺服器錯誤"))
        #expect(model.forecast == nil)
    }

    @Test("透支風險的標題", arguments: [(true, "存在透支風險"), (false, "現金流充裕安全")])
    func riskTitle(overdraft: Bool, expected: String) {
        #expect(forecast(overdraft: overdraft, minDate: today).riskTitle == expected)
    }

    /// 系統依地區的格式(DESIGN.md「日期」),不再是 web 的「2026/10/05」。預測是未來 30 天，跨年時才寫年份。
    @Test("最低餘額的發生日期、預定收支日是「10月5日」這種系統格式，不是今年的加上年份;沒有變動時顯示「無變動」")
    func dateTexts() async throws {
        let model = ForecastModel(
            repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(),
            locale: Locale(identifier: "zh_Hant_TW"), today: { today }
        )
        await model.load()
        let loaded = try #require(model.forecast)

        #expect(model.minDateText(of: loaded) == "10月5日")
        #expect(loaded.events.map { model.dateText($0.date) } == ["10月5日", "10月25日"])
        #expect(model.dateText(CalendarDay(year: 2027, month: 1, day: 3)) == "2027年1月3日")
        #expect(model.minDateText(of: forecast(overdraft: false, minDate: nil)) == "無變動")
    }

    @Test("預定收支依後端的順序")
    func events() async throws {
        let (model, _) = await loaded()
        let forecast = try #require(model.forecast)

        #expect(forecast.events.map(\.name) == ["房租", "薪水"])
        #expect(forecast.dailyBalances.count == 30)
    }

    @Test("購買力試算的金額要是正數", arguments: ["", "0", "-1", "abc", "1,000", "12.5"])
    func checkRequiresPositiveAmount(amount: String) async {
        let (model, repository) = await loaded()
        model.purchaseAmountText = amount

        await model.checkPurchase()

        #expect(model.purchaseError == "請輸入有效的購買金額")
        #expect(model.purchaseCheck == nil)
        #expect(await repository.checkedAmounts.isEmpty)
    }

    @Test("改成無效的金額時，清掉上一次的試算結果")
    func invalidAmountClearsPreviousResult() async {
        let (model, _) = await loaded()
        model.purchaseAmountText = "1000"
        await model.checkPurchase()
        #expect(model.purchaseCheck != nil)

        model.purchaseAmountText = "abc"
        await model.checkPurchase()

        #expect(model.purchaseCheck == nil)
        #expect(model.purchaseError == "請輸入有效的購買金額")
    }

    @Test("試算結果", arguments: [
        (1000, PurchaseVerdict.safe),
        (50000, .caution),
        (60000, .danger),
    ])
    func checkPurchase(amount: Int, verdict: PurchaseVerdict) async throws {
        let (model, repository) = await loaded()
        model.purchaseAmountText = "\(amount)"

        await model.checkPurchase()

        #expect(await repository.checkedAmounts == [Money(Decimal(amount))])
        #expect(model.purchaseCheck?.verdict == verdict)
        #expect(model.purchaseError == nil)
    }

    @Test("放心購買：顯示金額和最低餘額")
    func safeMessage() {
        let check = PurchaseCheck(amount: Money(1000), verdict: .safe, minBalance: Money(52440), affectedGoalNames: ["沖繩旅遊"])

        #expect(check.title == "放心購買")
        #expect(check.message == "花 $1,000 之後，未來 30 天的最低餘額仍有 $52,440,也不影響儲蓄目標的每月預留。")
    }

    @Test("審慎評估：列出受影響的儲蓄目標，用「、」串接")
    func cautionMessage() {
        let check = PurchaseCheck(amount: Money(50000), verdict: .caution, minBalance: Money(3440), affectedGoalNames: ["沖繩旅遊", "緊急備用金"])

        #expect(check.title == "審慎評估")
        #expect(check.message == "花 $50,000 不會透支，但會壓縮儲蓄目標的每月預留(可能影響沖繩旅遊、緊急備用金)。建議延後購買或調降金額。")
    }

    @Test("不建議購買：顯示最低餘額")
    func dangerMessage() {
        let check = PurchaseCheck(amount: Money(60000), verdict: .danger, minBalance: Money(-6560), affectedGoalNames: [])

        #expect(check.title == "不建議購買")
        #expect(check.message == "花 $60,000 之後，未來 30 天的餘額最低會跌到 -$6,560。")
    }

    @Test("試算失敗時顯示後端的訊息")
    func checkFailure() async {
        let (model, repository) = await loaded()
        await repository.fail(with: .rejected("請輸入有效金額"))
        model.purchaseAmountText = "100"

        await model.checkPurchase()

        #expect(model.purchaseError == "請輸入有效金額")
        #expect(model.purchaseCheck == nil)
    }

    @Test("資料版本改變後重抓(週期收支、資產帳戶或儲蓄目標改了，預測就會變)")
    func refreshesOnDataVersionChange() async {
        let dataVersion = DataVersion()
        let repository = InMemoryForecastRepository.sample(today: today)
        let model = ForecastModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        let fetches = await repository.fetchCount

        await model.refreshIfStale()
        #expect(await repository.fetchCount == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await repository.fetchCount > fetches)
    }

    // MARK: 視角(上游 ADR 0016、#153)

    private func scoped(
        gate: Gate? = nil, defaults: UserDefaults? = nil
    ) -> (ForecastModel, InMemoryForecastRepository) {
        let sample = InMemoryForecastRepository.sample(today: today)
        let repository = gate == nil ? sample : InMemoryForecastRepository(
            forecasts: Dictionary(uniqueKeysWithValues: ViewScope.allCases.map { ($0, CashFlowForecast(
                dailyBalances: [DailyBalance(date: today, balance: Money(Decimal($0 == .all ? 1 : 2)))],
                minBalance: Money(Decimal($0 == .all ? 1 : 2)), minDate: today, willOverdraft: false, events: []
            )) }),
            gate: gate
        ) { amount, _ in PurchaseCheck(amount: amount, verdict: .safe, minBalance: .zero, affectedGoalNames: []) }
        let model = ForecastModel(
            repository: repository, dataVersion: DataVersion(),
            defaults: defaults ?? UserDefaults(suiteName: "ForecastTests.\(UUID().uuidString)")!, today: { today }
        )
        return (model, repository)
    }

    @Test("視角預設是全部;選過的視角記在 UserDefaults，下次沿用")
    func scopeIsRemembered() {
        let suite = "ForecastTests.remember.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (first, _) = scoped(defaults: defaults)
        #expect(first.scope == .all)

        first.scope = .personal
        let (second, _) = scoped(defaults: defaults)

        #expect(second.scope == .personal)
    }

    @Test("預測與購買力試算一律明確帶視角(全部也帶);起始餘額、最低餘額隨視角")
    func requestsFollowTheScope() async {
        let (model, repository) = scoped()

        await model.load()
        #expect(model.forecast?.minBalance == Money(53440))

        model.scope = .household
        await model.load()
        #expect(model.forecast?.minBalance == Money(18000), "公帳視角只算家庭公帳的帳戶與項目")

        model.purchaseAmountText = "10000"
        await model.checkPurchase()
        #expect(model.purchaseCheck?.minBalance == Money(8000))
        #expect(model.purchaseCheck?.affectedGoalNames == [], "公帳視角的試算不檢核個人儲蓄目標")
        #expect(await repository.requestedScopes == [.all, .household])
        #expect(await repository.checkedScopes == [.household])
    }

    @Test("換視角時購買力試算的結果清掉(不留上一個視角的結論)")
    func changingScopeClearsThePurchaseCheck() async {
        let (model, _) = scoped()
        await model.load()
        model.purchaseAmountText = "1000"
        await model.checkPurchase()
        #expect(model.purchaseCheck != nil)

        model.scope = .personal

        #expect(model.purchaseCheck == nil)
        #expect(model.purchaseError == nil)
    }

    @Test("換了視角之後才回來的舊視角回應不蓋掉畫面", .timeLimit(.minutes(1)))
    func staleScopeResponseIsDropped() async {
        let gate = Gate()
        let (model, _) = scoped(gate: gate)

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        model.scope = .personal
        await gate.open()
        await loading.value

        #expect(model.forecast == nil, "全部視角的舊回應不該套用到個人私帳")
        #expect(model.phase == .loading)
    }

    // MARK: 預定收支列:歸屬與資產帳戶(上游 ADR 0016、0017,#155)

    @Test("預定收支列：左邊「日期・歸屬」，右邊金額下面是資產帳戶名稱(沒有帳戶就沒有這一行)")
    func eventRowTexts() {
        let model = ForecastModel(
            repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(),
            defaults: UserDefaults(suiteName: "ForecastTests.\(UUID().uuidString)")!, locale: Locale(identifier: "zh_Hant_TW"),
            today: { today }
        )
        let rent = ForecastEvent(
            date: CalendarDay(year: 2026, month: 10, day: 5), name: "房租", type: .expense, amount: Money(12000),
            isShared: true, accountName: "洋蔥玉山-共同基金"
        )
        let cardDue = ForecastEvent(
            date: CalendarDay(year: 2026, month: 10, day: 20), name: "💳 繳卡費 · 玉山 U Bear", type: .expense, amount: Money(8586),
            isShared: false, accountName: "玉山 U Bear"
        )
        let salary = ForecastEvent(
            date: CalendarDay(year: 2026, month: 10, day: 25), name: "薪水", type: .income, amount: Money(52000)
        )

        #expect(model.subtitle(of: rent) == "10月5日・家庭公帳")
        #expect(model.subtitle(of: cardDue) == "10月20日・個人私帳")
        #expect(model.subtitle(of: salary) == "10月25日・個人私帳")
        #expect(model.accountText(of: rent) == "洋蔥玉山-共同基金")
        #expect(model.accountText(of: salary) == nil)
        #expect(model.spokenText(of: rent) == "房租,10月5日,家庭公帳,帳戶 洋蔥玉山-共同基金,支出 12,000 元")
        #expect(model.spokenText(of: salary) == "薪水,10月25日,個人私帳,收入 52,000 元")
        #expect(model.spokenText(of: cardDue).contains("繳卡費"), "事件名稱照後端念")
    }
}
