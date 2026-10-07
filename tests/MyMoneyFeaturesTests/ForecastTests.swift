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

    @Test("預測頁的期程文字跟著後端的 60 天(b1f6067)")
    func horizonTexts() {
        #expect(ForecastHorizon.days == 60)
        #expect(ForecastModel.chartTitle == "未來 60 天逐日餘額")
        #expect(ForecastModel.eventsCountTitle == "未來 60 天的預定收支")
        #expect(ForecastModel.noEventsText == "未來 60 天沒有預定收支")
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

    /// 系統依地區的格式(DESIGN.md「日期」),不再是 web 的「2026/10/05」。預測是未來 60 天，跨年時才寫年份。
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
        #expect(forecast.dailyBalances.count == ForecastHorizon.days)
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
        #expect(check.message == "花 $1,000 之後，未來 60 天的最低餘額仍有 $52,440,也不影響儲蓄目標的每月預留。")
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
        #expect(check.message == "花 $60,000 之後，未來 60 天的餘額最低會跌到 −$6,560。")
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
            date: CalendarDay(year: 2026, month: 10, day: 20), name: "繳卡費 · 玉山 U Bear（已出帳 $5,000 + 待出帳 $3,586）", type: .expense, amount: Money(8586),
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
        #expect(model.spokenText(of: cardDue).contains("繳卡費 · 玉山 U Bear（已出帳 $5,000 + 待出帳 $3,586）"), "事件名稱照後端念，含組成")
    }

    // MARK: 起始餘額(上游 5b2faa6，#195)

    private func startingForecast(start: Int?, cash: Int?, bank: Int?) -> CashFlowForecast {
        CashFlowForecast(
            dailyBalances: [], minBalance: .zero, minDate: nil, willOverdraft: false, events: [],
            startingBalance: start.map { Money(Decimal($0)) }, cashTotal: cash.map { Money(Decimal($0)) },
            bankTotal: bank.map { Money(Decimal($0)) }
        )
    }

    @Test("起始餘額:主數字加「現金」「活存帳戶」兩行,三個數字照後端、不寫成算式")
    func startingBalanceSummary() throws {
        let model = ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion())

        let summary = try #require(model.startingBalance(of: startingForecast(start: 102950, cash: 1750, bank: 101200)))

        #expect(summary.amount == Money(102950))
        #expect(summary.detail == "現金 $1,750・活存帳戶 $101,200")
        #expect(summary.note == nil, "起始餘額等於現金加活存帳戶時不加說明")
    }

    @Test("起始餘額比現金加活存帳戶少時,說明已先扣掉繳款日不在未來 60 天內的信用卡待繳款")
    func startingBalanceDeduction() throws {
        let model = ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion())

        let summary = try #require(model.startingBalance(of: startingForecast(start: 86570, cash: 1750, bank: 101200)))

        #expect(summary.note == "已先扣掉繳款日不在未來 60 天內的信用卡待繳款")
    }

    @Test("舊回應沒有起始餘額,或缺少現金、活存帳戶其中一個:不顯示這一組")
    func startingBalanceMissing() {
        let model = ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion())

        #expect(model.startingBalance(of: startingForecast(start: nil, cash: nil, bank: nil)) == nil)
        #expect(model.startingBalance(of: startingForecast(start: 100, cash: 50, bank: nil)) == nil)
    }

    @Test("記憶體替身的預測帶起始餘額,畫面跟著視角")
    func sampleHasStartingBalance() async throws {
        // 用獨立的 UserDefaults:`scope` 會寫進 `.standard`,不隔離會污染其他測試。
        let model = ForecastModel(
            repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(),
            defaults: UserDefaults(suiteName: "ForecastTests.\(UUID().uuidString)")!
        )
        await model.load()
        let allForecast = try #require(model.forecast)
        let all = try #require(model.startingBalance(of: allForecast))
        #expect(all.amount == Money(65440))

        model.scope = .household
        await model.load()
        let householdForecast = try #require(model.forecast)
        let household = try #require(model.startingBalance(of: householdForecast))
        #expect(household.amount == Money(30000))
    }

    // MARK: 預測事件已繳(上游 ADR 0018，#182)

    private func rentEvent(_ model: ForecastModel) throws -> ForecastEvent {
        try #require(model.forecast?.events.first { $0.name == "房租" })
    }

    @Test("樣本的事件都有識別碼、未繳、能勾選")
    func sampleEventsCanBeSettled() async throws {
        let (model, _) = await loaded()

        let events = try #require(model.forecast?.events)
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.key != nil && !$0.isSettled && $0.canSettle })
    }

    @Test("勾選已繳:送出識別碼與 true，成功後重抓預測——事件標成已繳、最低餘額由後端重算(client 不重算)")
    func settleReloadsTheForecast() async throws {
        let (model, repository) = await loaded()
        let before = try #require(model.forecast?.minBalance)
        let rent = try rentEvent(model)

        await model.setSettled(true, for: rent)

        let requests = await repository.settleRequests
        #expect(requests.count == 1)
        #expect(requests.first?.key == rent.key)
        #expect(requests.first?.settled == true)
        #expect(try rentEvent(model).isSettled)
        #expect(try #require(model.forecast?.minBalance) > before, "已繳的房租不再計入最低餘額")
        #expect(model.settleError == nil)
        #expect(model.settlingKeys.isEmpty)
    }

    @Test("勾選已繳成功後遞增資料版本(總覽「接下來 60 天」等其他畫面跟著重抓，#189);失敗時不遞增")
    func settleBumpsTheDataVersion() async throws {
        let (model, repository) = await loaded()
        let before = model.dataVersion.value

        await model.setSettled(true, for: try rentEvent(model))
        let afterSuccess = model.dataVersion.value
        #expect(afterSuccess > before)

        await repository.fail(with: .rejected("壞了"))
        await model.setSettled(false, for: try rentEvent(model))
        #expect(model.dataVersion.value == afterSuccess)
    }

    @Test("再點一次取消已繳")
    func unsettle() async throws {
        let (model, repository) = await loaded()
        let rent = try rentEvent(model)
        await model.setSettled(true, for: rent)

        await model.setSettled(false, for: try rentEvent(model))

        #expect(await repository.settleRequests.map(\.settled) == [true, false])
        #expect(try !rentEvent(model).isSettled)
    }

    @Test("送出期間這一筆停用(不能連點)，完成後恢復", .timeLimit(.minutes(1)))
    func settlingKeyWhileSending() async throws {
        let gate = Gate()
        let (model, repository) = await loaded()
        await repository.holdSettling(with: gate)
        let rent = try rentEvent(model)

        let sending = Task { await model.setSettled(true, for: rent) }
        await gate.waitUntilReached()
        let key = try #require(rent.key)
        #expect(model.settlingKeys == [key])
        await model.setSettled(true, for: rent)
        #expect(await repository.settleRequests.count == 1, "送出期間再點不該多送一次")
        await gate.open()
        await sending.value

        #expect(model.settlingKeys.isEmpty)
    }

    @Test("失敗時顯示後端的訊息、事件維持原狀")
    func settleFailure() async throws {
        let (model, repository) = await loaded()
        let rent = try rentEvent(model)
        await repository.fail(with: .rejected("無權限勾選他人的私帳事件"))

        await model.setSettled(true, for: rent)

        #expect(model.settleError == "無權限勾選他人的私帳事件")
        #expect(try !rentEvent(model).isSettled)
        #expect(model.settlingKeys.isEmpty)
    }

    @Test("不能勾選的事件(沒有識別碼或 can_settle 為 false)不送請求")
    func unsettleableEventsAreIgnored() async throws {
        let (model, repository) = await loaded()
        let locked = ForecastEvent(date: today, name: "他人的私帳", type: .expense, amount: Money(1), key: "k", canSettle: false)
        let legacy = ForecastEvent(date: today, name: "舊回應", type: .expense, amount: Money(1))

        await model.setSettled(true, for: locked)
        await model.setSettled(true, for: legacy)

        #expect(await repository.settleRequests.isEmpty)
    }

    @Test("已繳的事件:畫面寫「已繳(不計入預測)」，VoiceOver 念出已繳")
    func settledTexts() {
        let model = ForecastModel(
            repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(),
            defaults: UserDefaults(suiteName: "ForecastTests.\(UUID().uuidString)")!, locale: Locale(identifier: "zh_Hant_TW"),
            today: { today }
        )
        let paid = ForecastEvent(
            date: CalendarDay(year: 2026, month: 10, day: 5), name: "房租", type: .expense, amount: Money(12000),
            key: "k", isSettled: true, canSettle: true
        )
        let open = ForecastEvent(
            date: CalendarDay(year: 2026, month: 10, day: 5), name: "房租", type: .expense, amount: Money(12000),
            key: "k", canSettle: true
        )

        #expect(model.settledNote(of: paid) == "已繳(不計入預測)")
        #expect(model.settledNote(of: open) == nil)
        #expect(model.spokenText(of: paid) == "房租,10月5日,個人私帳,支出 12,000 元,已繳，不計入預測")
        #expect(model.spokenText(of: open) == "房租,10月5日,個人私帳,支出 12,000 元")
    }
}
