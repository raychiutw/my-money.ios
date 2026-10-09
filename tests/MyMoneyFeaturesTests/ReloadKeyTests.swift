import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 重載鍵(#211 第 1 項):畫面的 `.task(id:)` 與 `refreshIfStale()` 看同一把鍵,「什麼變了要重載」只在 model 定義。
@MainActor
@Suite("重載鍵(reloadKey)")
struct ReloadKeyTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func overview(_ dataVersion: DataVersion) -> OverviewModel {
        let suite = "ReloadKeyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return OverviewModel(
            accounts: InMemoryAccountRepository.sample(),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(),
            dataVersion: dataVersion, defaults: defaults, today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    @Test("總覽:資料版本或視角變了，鍵就變;都沒變，鍵相同")
    func overviewKey() {
        let dataVersion = DataVersion()
        let model = overview(dataVersion)
        let first = model.reloadKey
        #expect(model.reloadKey == first)

        dataVersion.bump()
        #expect(model.reloadKey != first)

        let afterBump = model.reloadKey
        model.scope = .household
        #expect(model.reloadKey != afterBump)
    }

    @Test("統計:月份也是鍵的一部分")
    func statisticsKey() {
        let dataVersion = DataVersion()
        let model = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)), dataVersion: dataVersion, today: { today }
        )
        let first = model.reloadKey
        model.month = CalendarMonth(year: 2026, month: 8)
        #expect(model.reloadKey != first)

        model.month = CalendarMonth(today)
        #expect(model.reloadKey == first)

        model.scope = .personal
        #expect(model.reloadKey != first)

        model.scope = .all
        dataVersion.bump()
        #expect(model.reloadKey != first)
    }

    @Test("沒有檢視範圍的畫面:只有資料版本改變鍵")
    func goalsKey() {
        let dataVersion = DataVersion()
        let model = SavingsGoalsModel(repository: InMemorySavingsGoalRepository.sample(), dataVersion: dataVersion)
        let first = model.reloadKey
        #expect(model.reloadKey == first)
        dataVersion.bump()
        #expect(model.reloadKey != first)
    }
}
