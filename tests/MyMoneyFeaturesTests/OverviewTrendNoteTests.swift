import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 首頁走勢線的說明(#321):淨可用餘額是負的、預測最低餘額卻不是負的,才說明為什麼兩邊正負不同。
@MainActor
@Suite("首頁走勢線說明:淨可用餘額與預測正負不同時才出現")
struct OverviewTrendNoteTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 3)

    private func summary(available: Int) -> BalanceSummary {
        BalanceSummary(
            bankBalanceTotal: Money(100), billedDebtTotal: .zero, unbilledDebtTotal: .zero,
            availableBalance: Money(Decimal(available)), monthlyAmortization: .zero, monthlySavingsReserve: .zero, disposableCash: .zero
        )
    }

    private func forecast(minBalance: Int) -> CashFlowForecast {
        CashFlowForecast(
            dailyBalances: [DailyBalance(date: today, balance: Money(Decimal(minBalance)))],
            minBalance: Money(Decimal(minBalance)), minDate: today, willOverdraft: minBalance < 0, events: []
        )
    }

    private func loaded(available: Int, minBalance: Int?) async -> OverviewModel {
        let forecastRepository = minBalance.map { value in
            InMemoryForecastRepository(forecast: forecast(minBalance: value)) {
                PurchaseCheck(amount: $0, verdict: .safe, minBalance: .zero, affectedGoalNames: [])
            }
        }
        let suite = "OverviewTrendNoteTests-\(UUID().uuidString)"
        let model = OverviewModel(
            accounts: InMemoryAccountRepository(accounts: SampleAccounts.all, summary: summary(available: available)),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(),
            forecast: forecastRepository,
            dataVersion: DataVersion(), defaults: UserDefaults(suiteName: suite)!, today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
        await model.load()
        return model
    }

    @Test("淨可用為負、預測最低餘額不為負:顯示說明")
    func showsWhenSignsDiffer() async {
        let model = await loaded(available: -17827, minBalance: 5000)
        #expect(model.forecastTrendNote == "預測已含未來收入與信用卡繳款日，所以和上面的淨可用餘額不同")
    }

    @Test("預測最低餘額剛好是 0 也算不為負")
    func zeroMinimumCounts() async {
        #expect(await loaded(available: -1, minBalance: 0).forecastTrendNote != nil)
    }

    @Test("淨可用不是負的:沒有說明")
    func noNoteWhenAvailableIsNotNegative() async {
        #expect(await loaded(available: 0, minBalance: 5000).forecastTrendNote == nil)
        #expect(await loaded(available: 23000, minBalance: 5000).forecastTrendNote == nil)
    }

    @Test("預測也會透支:兩邊都是負的,不需要說明")
    func noNoteWhenForecastAlsoOverdraws() async {
        #expect(await loaded(available: -17827, minBalance: -500).forecastTrendNote == nil)
    }

    @Test("沒有預測(取不到):沒有說明")
    func noNoteWithoutForecast() async {
        #expect(await loaded(available: -17827, minBalance: nil).forecastTrendNote == nil)
    }

    @Test("預測沒有逐日餘額(走勢線畫不出來):也不顯示說明,model 與畫面一致")
    func noNoteWithoutDailyBalances() async {
        let empty = CashFlowForecast(dailyBalances: [], minBalance: Money(5000), minDate: nil, willOverdraft: false, events: [])
        let repository = InMemoryForecastRepository(forecast: empty) {
            PurchaseCheck(amount: $0, verdict: .safe, minBalance: .zero, affectedGoalNames: [])
        }
        let model = OverviewModel(
            accounts: InMemoryAccountRepository(accounts: SampleAccounts.all, summary: summary(available: -100)),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(), forecast: repository,
            dataVersion: DataVersion(), defaults: UserDefaults(suiteName: "OverviewTrendNoteTests-\(UUID().uuidString)")!,
            today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
        await model.load()
        #expect(model.forecastTrendNote == nil)
    }
}
