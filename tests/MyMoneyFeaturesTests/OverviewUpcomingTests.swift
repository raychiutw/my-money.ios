import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽「接下來 30 天」:預定收支與已繳勾選(#189)")
struct OverviewUpcomingTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    init() {
        let suite = "OverviewUpcomingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(
        forecast: InMemoryForecastRepository?, dataVersion: DataVersion = DataVersion()
    ) -> OverviewModel {
        OverviewModel(
            accounts: InMemoryAccountRepository.sample(),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(), forecast: forecast, dataVersion: dataVersion, defaults: defaults,
            today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private func loaded(
        _ forecast: InMemoryForecastRepository? = .sample(today: CalendarDay(year: 2026, month: 9, day: 28)),
        dataVersion: DataVersion = DataVersion()
    ) async -> OverviewModel {
        let overview = model(forecast: forecast, dataVersion: dataVersion)
        await overview.load()
        return overview
    }

    private func rent(_ overview: OverviewModel) throws -> ForecastEvent {
        try #require(overview.upcomingEvents.first { $0.event.name == "房租" }).event
    }

    // MARK: 列出哪幾筆

    @Test("列出後端預測的預定收支:日期、名稱、歸屬、帶正負號的金額")
    func listsUpcomingEvents() async {
        let overview = await loaded()

        let rows = overview.upcomingEvents
        #expect(rows.map(\.event.name) == ["房租", "薪水"])
        #expect(rows.map(\.dateText) == ["10月5日", "10月25日"])
        #expect(rows.map(\.subtitle) == ["家庭公帳", "個人私帳"])
        #expect(rows.map(\.amountText) == ["−$12,000", "+$45,000"])
        #expect(rows.map(\.isIncome) == [false, true])
    }

    @Test("最多列 5 筆,順序跟後端一樣")
    func limitsToFiveEvents() async {
        let events = (1...7).map { index in
            ForecastEvent(
                date: CalendarDay(year: 2026, month: 10, day: index), name: "事件\(index)", type: .expense, amount: Money(Decimal(index)),
                key: "k\(index)", canSettle: true
            )
        }
        let forecast = CashFlowForecast(dailyBalances: [], minBalance: .zero, minDate: nil, willOverdraft: false, events: events)
        let overview = await loaded(InMemoryForecastRepository(forecast: forecast) { PurchaseCheck(amount: $0, verdict: .safe, minBalance: .zero, affectedGoalNames: []) })

        #expect(overview.upcomingEvents.map(\.event.name) == ["事件1", "事件2", "事件3", "事件4", "事件5"])
    }

    @Test("跟著首頁的視角:公帳只有房租")
    func followsTheScope() async {
        let overview = model(forecast: .sample(today: today))
        overview.scope = .household

        await overview.load()

        #expect(overview.upcomingEvents.map(\.event.name) == ["房租"])
    }

    @Test("預測載入失敗或沒有預測來源時沒有這一區,其他照常")
    func noUpcomingWithoutForecast() async {
        let failing = InMemoryForecastRepository.sample(today: today)
        await failing.fail(with: .rejected("壞了"))
        let failed = await loaded(failing)
        #expect(failed.phase == .loaded)
        #expect(failed.upcomingEvents.isEmpty)

        let none = await loaded(nil)
        #expect(none.upcomingEvents.isEmpty)
    }

    // MARK: 已繳

    @Test("已繳的事件仍列出,但標「已繳」;VoiceOver 念出已繳與不計入預測")
    func settledRow() async throws {
        let overview = await loaded()
        await overview.setSettled(true, for: try rent(overview))

        let row = try #require(overview.upcomingEvents.first { $0.event.name == "房租" })
        #expect(row.event.isSettled)
        #expect(row.subtitle == "家庭公帳・已繳")
        #expect(row.spokenText == "房租，10月5日，家庭公帳，支出 12,000 元，已繳，不計入預測")
        #expect(row.checkLabel == "取消已繳")
        let open = try #require(overview.upcomingEvents.first { $0.event.name == "薪水" })
        #expect(open.spokenText == "薪水，10月25日，個人私帳，收入 45,000 元")
        #expect(open.checkLabel == "標示為已繳")
    }

    @Test("勾選已繳:送出識別碼與 true,成功後遞增資料版本並重抓——最低餘額由後端重算")
    func settleBumpsTheDataVersionAndReloads() async throws {
        let repository = InMemoryForecastRepository.sample(today: today)
        let dataVersion = DataVersion()
        let overview = await loaded(repository, dataVersion: dataVersion)
        let before = try #require(overview.forecast?.minBalance)
        let version = dataVersion.value
        let event = try rent(overview)

        await overview.setSettled(true, for: event)

        let requests = await repository.settleRequests
        #expect(requests.count == 1 && requests.first?.key == event.key && requests.first?.settled == true)
        #expect(dataVersion.value > version, "其他畫面(預測頁)才會跟著重抓")
        #expect(try #require(overview.forecast?.minBalance) > before)
        #expect(try rent(overview).isSettled)
        #expect(overview.settleError == nil && overview.settlingKeys.isEmpty)
    }

    @Test("再點一次取消已繳")
    func unsettle() async throws {
        let repository = InMemoryForecastRepository.sample(today: today)
        let overview = await loaded(repository)
        await overview.setSettled(true, for: try rent(overview))

        await overview.setSettled(false, for: try rent(overview))

        #expect(await repository.settleRequests.map(\.settled) == [true, false])
        #expect(try !rent(overview).isSettled)
    }

    @Test("送出期間那一筆停用,不能連點", .timeLimit(.minutes(1)))
    func settlingKeyWhileSending() async throws {
        let gate = Gate()
        let repository = InMemoryForecastRepository.sample(today: today)
        let overview = await loaded(repository)
        await repository.holdSettling(with: gate)
        let event = try rent(overview)

        let sending = Task { await overview.setSettled(true, for: event) }
        await gate.waitUntilReached()
        #expect(overview.settlingKeys == [try #require(event.key)])
        await overview.setSettled(true, for: event)
        #expect(await repository.settleRequests.count == 1, "送出期間再點不該多送一次")
        await gate.open()
        await sending.value

        #expect(overview.settlingKeys.isEmpty)
    }

    @Test("失敗時顯示後端的訊息,事件維持原狀")
    func settleFailure() async throws {
        let repository = InMemoryForecastRepository.sample(today: today)
        let overview = await loaded(repository)
        let event = try rent(overview)
        await repository.fail(with: .rejected("無權限勾選他人的私帳事件"))

        await overview.setSettled(true, for: event)

        #expect(overview.settleError == "無權限勾選他人的私帳事件")
        #expect(try !rent(overview).isSettled)
        overview.clearSettleError()
        #expect(overview.settleError == nil)
    }

    @Test("不能勾選的事件(沒有識別碼或 can_settle 為 false)不送請求,也沒有勾選圓圈")
    func unsettleableEvents() async {
        let locked = ForecastEvent(date: today, name: "他人的私帳", type: .expense, amount: Money(1), key: "k", canSettle: false)
        let legacy = ForecastEvent(date: today, name: "舊回應", type: .expense, amount: Money(1))
        let forecast = CashFlowForecast(dailyBalances: [], minBalance: .zero, minDate: nil, willOverdraft: false, events: [locked, legacy])
        let repository = InMemoryForecastRepository(forecast: forecast) { PurchaseCheck(amount: $0, verdict: .safe, minBalance: .zero, affectedGoalNames: []) }
        let overview = await loaded(repository)

        await overview.setSettled(true, for: locked)
        await overview.setSettled(true, for: legacy)

        #expect(await repository.settleRequests.isEmpty)
        #expect(overview.upcomingEvents.map(\.isSettleable) == [false, false])
    }

    @Test("能勾選的事件有勾選圓圈")
    func settleableEvents() async {
        let overview = await loaded()

        #expect(overview.upcomingEvents.map(\.isSettleable) == [true, true])
    }
}
