import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 總覽切換視角時只重抓隨視角變動的資料(上游 2adbc5d、ADR 0023「前端按需請求」;#246):
/// 預算與儲蓄目標不隨視角變動，載入過就保留，只在資料版本變動或第一次載入時重抓。
@MainActor
@Suite("總覽按需請求")
struct OverviewSelectiveRefetchTests {
    private let day = CalendarDay(year: 2026, month: 9, day: 28)

    private struct Fixture {
        let model: OverviewModel
        let accounts: InMemoryAccountRepository
        let statistics: InMemoryStatisticsRepository
        let goals: InMemorySavingsGoalRepository
        let dataVersion: DataVersion
    }

    private func goalsValue(_ model: OverviewModel) -> String? {
        model.entries.first { $0.destination == .goals }?.value
    }

    private func fixture() -> Fixture {
        let dataVersion = DataVersion()
        let accounts = InMemoryAccountRepository.sample()
        let statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(day))
        let goals = InMemorySavingsGoalRepository.sample()
        let model = OverviewModel(
            accounts: accounts, transactions: InMemoryTransactionRepository(transactions: []), statistics: statistics, goals: goals,
            context: SessionContext(dataVersion: dataVersion, defaults: UserDefaults.isolated(), today: { day })
        )
        return Fixture(model: model, accounts: accounts, statistics: statistics, goals: goals, dataVersion: dataVersion)
    }

    @Test("第一次載入:預算與儲蓄目標各抓一次")
    func firstLoadFetchesEverything() async {
        let f = fixture()

        await f.model.load()

        #expect(await f.statistics.budgetQueries.count == 1)
        #expect(await f.goals.fetchCount == 1)
    }

    @Test("只切換視角:帳戶與每月統計重抓，預算與儲蓄目標不重抓，畫面上的內容還在")
    func scopeSwitchKeepsScopeInvariantData() async {
        let f = fixture()
        await f.model.load()
        let monthlyBefore = await f.statistics.monthlyQueries.count
        let overBudgets = f.model.overBudgets
        let goalsBefore = goalsValue(f.model)
        #expect(goalsBefore != nil)

        f.model.scope = .household
        await f.model.refreshIfStale()

        #expect(await f.statistics.monthlyQueries.count == monthlyBefore + 1, "每月統計隨視角變動，要重抓")
        #expect(await f.statistics.budgetQueries.count == 1, "預算不隨視角變動，不重抓")
        #expect(await f.goals.fetchCount == 1, "儲蓄目標不隨視角變動，不重抓")
        #expect(f.model.overBudgets.map(\.category) == overBudgets.map(\.category))
        #expect(goalsValue(f.model) == goalsBefore, "儲蓄目標那一格的內容還在")
    }

    @Test("資料版本變動(記帳、設定預算…):預算與儲蓄目標也重抓")
    func dataVersionChangeRefetchesEverything() async {
        let f = fixture()
        await f.model.load()

        f.dataVersion.bump()
        await f.model.refreshIfStale()

        #expect(await f.statistics.budgetQueries.count == 2)
        #expect(await f.goals.fetchCount == 2)
    }

    @Test("視角與資料版本一起變:全部重抓")
    func scopeAndVersionTogether() async {
        let f = fixture()
        await f.model.load()

        f.model.scope = .personal
        f.dataVersion.bump()
        await f.model.refreshIfStale()

        #expect(await f.statistics.budgetQueries.count == 2)
        #expect(await f.goals.fetchCount == 2)
    }

    @Test("上一次儲蓄目標沒抓到:下次切換視角時再試一次(不把失敗當成已載入)")
    func failedGoalsAreRetried() async {
        let f = fixture()
        await f.goals.fail(with: .unreadableResponse)
        await f.model.load()
        #expect(goalsValue(f.model) == nil)
        await f.goals.clearFailure()

        f.model.scope = .household
        await f.model.refreshIfStale()

        #expect(await f.goals.fetchCount == 2)
        #expect(goalsValue(f.model) != nil)
    }

    @Test("月份跨過去:預算是「本月」的，即使視角與資料版本都沒變，再載入時也要重抓")
    func monthRolloverRefetchesBudgets() async {
        final class Clock { var now = CalendarDay(year: 2026, month: 9, day: 30) }
        let clock = Clock()
        let statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(clock.now))
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sample(), transactions: InMemoryTransactionRepository(transactions: []),
            statistics: statistics, goals: InMemorySavingsGoalRepository.sample(),
            context: SessionContext(dataVersion: DataVersion(), defaults: UserDefaults.isolated(), today: { clock.now })
        )
        await model.load()
        #expect(await statistics.budgetQueries == [CalendarMonth(year: 2026, month: 9)])

        clock.now = CalendarDay(year: 2026, month: 10, day: 1)
        await model.load()

        #expect(await statistics.budgetQueries == [CalendarMonth(year: 2026, month: 9), CalendarMonth(year: 2026, month: 10)])
    }
}
