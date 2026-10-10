import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 登入 session 的共同建構脈絡(#227):資料版本、今天、locale、defaults 一起傳，model 只收它一個參數。
@MainActor
@Suite("共同建構脈絡(SessionContext)")
struct SessionContextTests {
    private let day = CalendarDay(year: 2026, month: 9, day: 28)

    @Test("預設值:新的資料版本、標準 defaults、跟著系統的 locale、台灣時間的今天")
    func defaultValues() {
        let context = SessionContext()

        #expect(context.dataVersion.value == 0)
        #expect(context.defaults === UserDefaults.standard)
        #expect(context.locale == Locale.autoupdatingCurrent)
        #expect(context.today() == CalendarDay.today())
    }

    @Test("給的值原樣帶過去;同一份資料版本在複製出來的脈絡之間共用")
    func customValues() {
        let version = DataVersion()
        let defaults = UserDefaults.isolated()
        let taiwan = Locale(identifier: "zh_Hant_TW")
        let context = SessionContext(dataVersion: version, defaults: defaults, locale: taiwan, today: { day })

        #expect(context.dataVersion === version)
        #expect(context.defaults === defaults)
        #expect(context.locale == taiwan)
        #expect(context.today() == day)

        let copy = context
        version.bump()
        #expect(copy.dataVersion.value == 1)
    }

    @Test("預測、統計、儲蓄目標:用脈絡建立，跟用個別參數建立行為一樣(資料版本、今天、defaults 都來自脈絡)")
    func forecastStatisticsAndGoalsTakeAContext() {
        let version = DataVersion()
        let defaults = UserDefaults.isolated()
        defaults.set("household", forKey: "forecast.scope")
        defaults.set("personal", forKey: "statistics.scope")
        let context = SessionContext(dataVersion: version, defaults: defaults, locale: Locale(identifier: "zh_Hant_TW"), today: { day })

        let forecast = ForecastModel(repository: InMemoryForecastRepository.sampleForToday(), context: context)
        let statistics = StatisticsModel(repository: InMemoryStatisticsRepository.sample(month: CalendarMonth(day)), context: context)
        let goals = SavingsGoalsModel(repository: InMemorySavingsGoalRepository.sample(), context: context)

        #expect(forecast.dataVersion === version)
        #expect(statistics.dataVersion === version)
        #expect(goals.dataVersion === version)
        #expect(forecast.scope == .household, "視角記憶用脈絡的 defaults")
        #expect(statistics.scope == .personal)
        #expect(statistics.currentMonth == CalendarMonth(day), "今天來自脈絡")
        #expect(statistics.monthTitle == "2026年9月", "locale 來自脈絡")

        version.bump()
        #expect(forecast.reloadKey.version == 1)
        #expect(goals.reloadKey.version == 1)
    }

    @Test("總覽、週期收支、帳戶:用脈絡建立(資料版本、今天、locale、defaults 都來自脈絡;權限另外傳)")
    func overviewRecurringAndAccountsTakeAContext() {
        let version = DataVersion()
        let defaults = UserDefaults.isolated()
        defaults.set("household", forKey: "overview.scope")
        defaults.set("personal", forKey: "recurring.scope")
        defaults.set("household", forKey: "accounts.scope")
        let context = SessionContext(dataVersion: version, defaults: defaults, locale: Locale(identifier: "zh_Hant_TW"), today: { day })

        let overview = OverviewModel(
            accounts: InMemoryAccountRepository.sample(), transactions: InMemoryTransactionRepository(transactions: []),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(day)), goals: InMemorySavingsGoalRepository.sample(),
            context: context
        )
        let recurring = RecurringModel(
            repository: InMemoryRecurringRepository.sample(), accounts: InMemoryAccountRepository.sample(), context: context
        )
        let accounts = AccountsModel(repository: InMemoryAccountRepository.sample(), context: context)

        #expect(overview.dataVersion === version)
        #expect(recurring.dataVersion === version)
        #expect(accounts.dataVersion === version)
        #expect(overview.scope == .household)
        #expect(recurring.scope == .personal)
        #expect(accounts.scope == .household)

        version.bump()
        #expect(overview.reloadKey.version == 1)
        #expect(recurring.reloadKey.version == 1)
        #expect(accounts.reloadKey.version == 1)
    }

    @Test("記帳、家庭、信用卡詳細頁:用脈絡建立(資料版本、今天、locale 來自脈絡;權限與登入的人另外傳)")
    func transactionsHouseholdAndCardDetailTakeAContext() {
        let version = DataVersion()
        let context = SessionContext(
            dataVersion: version, defaults: UserDefaults.isolated(), locale: Locale(identifier: "zh_Hant_TW"), today: { day }
        )

        let transactions = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: []), accounts: InMemoryAccountRepository.sample(),
            currentUser: InMemoryAuthRepository.Member.sample.user.id, context: context
        )
        let household = HouseholdModel(
            repository: InMemoryHouseholdRepository.sample(), accounts: InMemoryAccountRepository.sample(),
            currentUser: InMemoryAuthRepository.Member.sample.user.id, context: context
        )
        let detail = CreditCardDetailModel(
            card: SampleAccounts.card, bankAccounts: [], loadedVersion: nil, scope: .all,
            repository: InMemoryAccountRepository.sample(), context: context
        )

        #expect(transactions.dataVersion === version)
        #expect(detail.dataVersion === version)
        #expect(transactions.filter.to == day, "預設區間的迄日是脈絡的今天")

        // 脈絡的今天設在 2024 年:同一年的日期不寫年份;如果「今天」是系統的(2026 年)就會寫成「2024年9月1日」。
        let in2024 = SessionContext(
            defaults: UserDefaults.isolated(), locale: Locale(identifier: "zh_Hant_TW"), today: { CalendarDay(year: 2024, month: 9, day: 28) }
        )
        let household2024 = HouseholdModel(
            repository: InMemoryHouseholdRepository.sample(), accounts: InMemoryAccountRepository.sample(), context: in2024
        )
        #expect(household2024.dateText(CalendarDay(year: 2024, month: 9, day: 1)) == "9月1日", "日期格式來自脈絡的今天與 locale")
        _ = household

        version.bump()
        #expect(transactions.reloadKey.version == 1)
        #expect(detail.reloadKey.version == 1)
    }
}
