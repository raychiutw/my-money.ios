import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 視角記憶(#220):選過的視角記在 UserDefaults，下次沿用;預設全部。
@MainActor
@Suite("視角記憶(ScopeMemory)")
struct ScopeMemoryTests {
    private let suite = "ScopeMemoryTests-\(UUID().uuidString)"
    private var defaults: UserDefaults {
        UserDefaults(suiteName: suite)!
    }

    @Test("沒有記過:預設全部")
    func defaultsToAll() {
        defaults.removePersistentDomain(forName: suite)
        let memory = ScopeMemory<ViewScope>(defaults: defaults, key: "x.scope")
        #expect(memory.load() == .all)
    }

    @Test("寫入後讀回同一個值，ViewScope 與 AccountScope 各自獨立")
    func roundTrip() {
        defaults.removePersistentDomain(forName: suite)
        ScopeMemory<ViewScope>(defaults: defaults, key: "x.scope").save(.household)
        ScopeMemory<AccountScope>(defaults: defaults, key: "y.scope").save(.personal)
        #expect(ScopeMemory<ViewScope>(defaults: defaults, key: "x.scope").load() == .household)
        #expect(ScopeMemory<AccountScope>(defaults: defaults, key: "y.scope").load() == .personal)
        #expect(ScopeMemory<ViewScope>(defaults: defaults, key: "z.scope").load() == .all)
    }

    @Test("儲存的值看不懂:回到全部")
    func unknownValue() {
        defaults.removePersistentDomain(forName: suite)
        defaults.set("family-only", forKey: "x.scope")
        #expect(ScopeMemory<ViewScope>(defaults: defaults, key: "x.scope").load() == .all)
    }

    @Test("既有三個畫面的 key 不變，使用者已選過的視角不會被重設")
    func existingKeysAreStable() {
        defaults.removePersistentDomain(forName: suite)
        defaults.set("household", forKey: "overview.scope")
        defaults.set("personal", forKey: "forecast.scope")
        defaults.set("household", forKey: "recurring.scope")
        let version = DataVersion()
        let overview = OverviewModel(
            accounts: InMemoryAccountRepository.sample(),
            transactions: InMemoryTransactionRepository(transactions: []),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)),
            goals: InMemorySavingsGoalRepository.sample(), dataVersion: version, defaults: defaults,
            today: { CalendarDay(year: 2026, month: 9, day: 28) }, locale: Locale(identifier: "zh_Hant_TW")
        )
        #expect(overview.scope == .household)
    }

    @Test("統計與帳戶也記憶視角:換視角後重新建立 model 沿用")
    func statisticsAndAccountsRemember() {
        defaults.removePersistentDomain(forName: suite)
        let version = DataVersion()
        let statistics = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)), dataVersion: version,
            defaults: defaults, today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        statistics.scope = .personal
        let accounts = AccountsModel(
            repository: InMemoryAccountRepository.sample(), dataVersion: version, defaults: defaults,
            today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        accounts.scope = .household

        let statisticsAgain = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)), dataVersion: version,
            defaults: defaults, today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        let accountsAgain = AccountsModel(
            repository: InMemoryAccountRepository.sample(), dataVersion: version, defaults: defaults,
            today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        #expect(statisticsAgain.scope == .personal)
        #expect(accountsAgain.scope == .household)
    }

    @Test("建立 model、或存入與目前相同的值，都不寫入 UserDefaults")
    func constructionDoesNotWrite() {
        defaults.removePersistentDomain(forName: suite)
        let version = DataVersion()
        _ = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: version, defaults: defaults)
        _ = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)), dataVersion: version,
            defaults: defaults
        )
        #expect(defaults.string(forKey: "accounts.scope") == nil)
        #expect(defaults.string(forKey: "statistics.scope") == nil)

        ScopeMemory<ViewScope>(defaults: defaults, key: "x.scope").save(.all)
        #expect(defaults.string(forKey: "x.scope") == nil)
    }
}
