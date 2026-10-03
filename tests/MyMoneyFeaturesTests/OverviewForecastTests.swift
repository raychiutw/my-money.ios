import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽的 30 天走勢:後端依視角算的現金流預測，每個視角都顯示，失敗不影響其他區塊(#116、#153)")
struct OverviewForecastTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    init() {
        let suite = "OverviewForecastTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(forecast: InMemoryForecastRepository?) -> OverviewModel {
        OverviewModel(
            accounts: InMemoryAccountRepository.sample(),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(),
            forecast: forecast,
            dataVersion: DataVersion(), defaults: defaults, today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    @Test("載入總覽時一併取得後端的預測，視角是「全部」就提供走勢圖資料")
    func loadsTheForecastForTheAllScope() async {
        let repository = InMemoryForecastRepository.sample(today: today)
        let overview = model(forecast: repository)

        await overview.load()

        #expect(overview.phase == .loaded)
        #expect(overview.forecast?.dailyBalances.count == 30)
        #expect(overview.forecast?.minBalance == Money(53440))
        #expect(await repository.fetchCount == 1)
    }

    @Test("走勢圖的資料與 VoiceOver 摘要由 model 提供(日期用台灣時間的今天)")
    func providesTheTrendAndItsSpokenSummary() async {
        let overview = model(forecast: InMemoryForecastRepository.sample(today: today))
        #expect(overview.forecastTrend == nil)
        #expect(overview.forecastSummary == nil)

        await overview.load()

        #expect(overview.forecastTrend?.points.count == 30)
        #expect(overview.forecastSummary?.hasPrefix("未來 30 天預測餘額，最低餘額 53,440 元，") == true)
        #expect(overview.forecastSummary?.hasSuffix("不會透支") == true)
    }

    @Test("每個視角都有走勢圖資料，而且用該視角的預測(上游 ADR 0016:預測依視角分流)", arguments: [ViewScope.household, .personal])
    func forecastForEveryScope(scope: ViewScope) async {
        let repository = InMemoryForecastRepository.sample(today: today)
        let overview = model(forecast: repository)
        overview.scope = scope

        await overview.load()

        #expect(overview.phase == .loaded)
        #expect(overview.forecast?.dailyBalances.count == 30)
        #expect(overview.forecast?.minBalance == (scope == .household ? Money(18000) : Money(35440)))
        #expect(await repository.requestedScopes == [scope], "總覽用目前的視角取預測")
    }

    @Test("切換視角時走勢圖資料跟著：換成該視角的預測，切回全部又是整體的")
    func forecastFollowsTheScope() async {
        let overview = model(forecast: InMemoryForecastRepository.sample(today: today))
        await overview.load()
        #expect(overview.forecast?.minBalance == Money(53440))

        overview.scope = .household
        await overview.load()
        #expect(overview.forecast?.minBalance == Money(18000))

        overview.scope = .all
        await overview.load()
        #expect(overview.forecast?.minBalance == Money(53440))
    }

    @Test("預測載入失敗時，總覽其他資料照常載入、整體不是失敗狀態，只是沒有走勢圖")
    func forecastFailureDoesNotBreakTheOverview() async {
        let repository = InMemoryForecastRepository.sample(today: today)
        await repository.fail(with: .rejected("預測失敗"))
        let overview = model(forecast: repository)

        await overview.load()

        #expect(overview.phase == .loaded, "預測失敗不該讓整個總覽失敗")
        #expect(overview.forecast == nil)
        #expect(overview.summary != nil, "其他資料要照常載入")
        #expect(!overview.recentTransactions.isEmpty)
    }

    @Test("沒有預測資料來源時(例如舊的呼叫端)總覽照常運作")
    func worksWithoutAForecastRepository() async {
        let overview = model(forecast: nil)

        await overview.load()

        #expect(overview.phase == .loaded)
        #expect(overview.forecast == nil)
    }
}

@Suite("30 天走勢的呈現:零線的位置、顏色切換點與 VoiceOver 摘要")
struct ForecastTrendTests {
    private func trend(_ balances: [Int], minDate: CalendarDay? = nil) -> ForecastTrend {
        let start = CalendarDay(year: 2026, month: 9, day: 28).startOfDay
        let days = balances.enumerated().map { index, value in
            DailyBalance(date: CalendarDay(date: start.addingTimeInterval(Double(index) * 86_400)), balance: Money(Decimal(value)))
        }
        let minimum = balances.min() ?? 0
        let forecast = CashFlowForecast(
            dailyBalances: days, minBalance: Money(Decimal(minimum)), minDate: minDate, willOverdraft: minimum < 0, events: []
        )
        return ForecastTrend(forecast: forecast)
    }

    @Test("有正有負:紅色從零線的位置開始(由上往下的比例)")
    func zeroFractionWhenTheLineCrossesZero() {
        // 最高 30、最低 -10 → 零線在由上往下 30/40 = 0.75 的位置。
        #expect(trend([30, 10, -10]).zeroFraction == 0.75)
    }

    @Test("全部不低於零:整條線一般色，沒有零線的切換點")
    func noSplitWhenNeverBelowZero() {
        #expect(trend([30, 10, 5]).zeroFraction == nil)
        #expect(!trend([30, 10, 5]).crossesZero)
    }

    @Test("全部低於零:整條線紅色")
    func allBelowZero() {
        let allNegative = trend([-5, -10, -20])
        #expect(allNegative.isEntirelyBelowZero)
        #expect(allNegative.zeroFraction == nil)
    }

    @Test("會透支時 VoiceOver 摘要指出最低餘額、日期與透支;不會透支時說明最低餘額")
    func spokenSummary() {
        let today = CalendarDay(year: 2026, month: 9, day: 28)
        let locale = Locale(identifier: "zh_Hant_TW")
        let overdraft = trend([30, -10, 5], minDate: CalendarDay(year: 2026, month: 9, day: 29))
        #expect(overdraft.spokenSummary(today: today, locale: locale) == "未來 30 天預測餘額，最低餘額 負 10 元，9月29日，會透支")

        let safe = trend([30, 20, 25], minDate: CalendarDay(year: 2026, month: 9, day: 29))
        #expect(safe.spokenSummary(today: today, locale: locale) == "未來 30 天預測餘額，最低餘額 20 元，9月29日，不會透支")
    }

    @Test("沒有任何一天時沒有圖")
    func empty() {
        let empty = ForecastTrend(forecast: CashFlowForecast(dailyBalances: [], minBalance: .zero, minDate: nil, willOverdraft: false, events: []))
        #expect(empty.points.isEmpty)
        #expect(empty.zeroFraction == nil)
    }
}
