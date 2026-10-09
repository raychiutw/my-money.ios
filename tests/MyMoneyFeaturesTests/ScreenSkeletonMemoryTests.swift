import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 其他畫面的骨架屏也跟著實際內容(#204 的核對):記帳、統計、預測、週期收支、儲蓄目標。
/// 每個畫面載入完成時記下各區塊的數量,下一次骨架照它畫;第一次沒有記錄時用預設。只記數量與狀態,不記內容。
@MainActor
@Suite("其他畫面的骨架屏數量記憶")
struct ScreenSkeletonMemoryTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let september = CalendarMonth(year: 2026, month: 9)

    private func defaults() -> UserDefaults {
        let suite = "ScreenSkeletonMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("週期收支:預設支出 3、收入 1;載入後記下實際的筆數")
    func recurring() async {
        let defaults = defaults()
        func make() -> RecurringModel {
            RecurringModel(
                repository: InMemoryRecurringRepository.sample(), accounts: InMemoryAccountRepository.sample(),
                dataVersion: DataVersion(), defaults: defaults, today: { today }
            )
        }
        let first = make()
        #expect(first.skeletonCounts == .init(expenses: 3, incomes: 1))

        await first.load()

        #expect(make().skeletonCounts == .init(expenses: first.expenses.count, incomes: first.incomes.count))
        #expect(first.expenses.count != 3 || first.incomes.count != 1, "範例資料的筆數要跟預設不同,測試才分得出有沒有記住")
    }

    @Test("儲蓄目標:預設有截止日 1、沒有截止日 1;載入後記下兩區的筆數")
    func goals() async {
        let defaults = defaults()
        func make() -> SavingsGoalsModel {
            SavingsGoalsModel(repository: InMemorySavingsGoalRepository.sample(), dataVersion: DataVersion(), defaults: defaults)
        }
        let first = make()
        #expect(first.skeletonCounts == .init(dated: 1, undated: 1))

        await first.load()

        #expect(make().skeletonCounts == .init(dated: first.datedGoals.count, undated: first.undatedGoals.count))
        #expect(first.datedGoals.count != 1 || first.undatedGoals.count != 1)
    }

    @Test("統計:預設分類 3、預算 3;載入後記下分類數與預算列數")
    func statistics() async {
        let defaults = defaults()
        func make() -> StatisticsModel {
            StatisticsModel(
                repository: InMemoryStatisticsRepository.sample(month: september), dataVersion: DataVersion(), defaults: defaults,
                today: { today }
            )
        }
        let first = make()
        #expect(first.skeletonCounts == .init(categories: 3, budgets: 3))

        await first.load()

        #expect(make().skeletonCounts == .init(categories: first.categoryExpenses.count, budgets: first.budgetRows.count))
    }

    @Test("預測:預設預定收支 3 筆、有起始餘額;載入後記下筆數與有沒有起始餘額")
    func forecast() async {
        let defaults = defaults()
        func make() -> ForecastModel {
            ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(), defaults: defaults)
        }
        let first = make()
        #expect(first.skeletonCounts == .init(events: 3, hasStartingBalance: true))

        await first.load()

        let loaded = first.forecast
        #expect(make().skeletonCounts == .init(events: loaded?.events.count ?? 0, hasStartingBalance: loaded?.startingBalance != nil))
    }

    @Test("記帳:預設兩天各 3、2 筆;載入後記下前三天的筆數(每天最多 4)")
    func transactions() async {
        let defaults = defaults()
        func make() -> TransactionsModel {
            TransactionsModel(
                repository: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
                dataVersion: DataVersion(), defaults: defaults, today: { today }
            )
        }
        let first = make()
        #expect(first.skeletonDayRows == [3, 2])

        await first.load()

        #expect(make().skeletonDayRows == first.days.prefix(3).map { min($0.transactions.count, 4) })
    }
}
