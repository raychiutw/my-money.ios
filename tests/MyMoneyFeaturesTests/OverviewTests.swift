import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽")
struct OverviewTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    private let accounts = InMemoryAccountRepository.sample()
    private let transactions: InMemoryTransactionRepository
    private let statistics: InMemoryStatisticsRepository
    private let goals = InMemorySavingsGoalRepository.sample()

    init() {
        let suite = "OverviewTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        transactions = InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today))
        statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(today))
    }

    private func model(dataVersion: DataVersion = DataVersion()) -> OverviewModel {
        OverviewModel(
            accounts: accounts, transactions: transactions, statistics: statistics, goals: goals,
            dataVersion: dataVersion, defaults: defaults, today: { today }
        )
    }

    private func loaded(dataVersion: DataVersion = DataVersion()) async -> OverviewModel {
        let model = model(dataVersion: dataVersion)
        await model.load()
        return model
    }

    @Test("帳戶一覽列出現金錢包;淨可用餘額的組成是「現金 + 活存 - 卡債」(web 的 Dashboard)")
    func availableBreakdownIncludesCash() async {
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sampleWithCash(), transactions: transactions, statistics: statistics,
            goals: goals, dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.cashWallets.map(\.name) == ["iOS 測試皮夾"])
        #expect(model.availableBreakdown == "現金 $1,500 + 活存 $50,000 - 卡債 $28,500")
    }

    @Test("視角也套用在資金指標和帳戶一覽(web 的 Dashboard 在 82d9124 起帶 scope)")
    func scopeAppliesToBalanceAndAccounts() async {
        let model = model()
        model.scope = .personal

        await model.load()

        #expect(await accounts.requestedScopes.last == .personal)
        #expect(await accounts.requestedSummaryScopes.last == .personal)
    }

    @Test("視角預設全部;選過的視角記在 UserDefaults,下次打開沿用")
    func scopeIsRemembered() {
        let first = model()
        #expect(first.scope == .all)

        first.scope = .household

        #expect(model().scope == .household)
    }

    @Test("最近 6 筆交易紀錄不限日期，依目前的視角查詢")
    func recentTransactionsQuery() async throws {
        let model = model()
        model.scope = .personal

        await model.load()

        let query = try #require(await transactions.queries.last)
        #expect(query.from == nil && query.to == nil)
        #expect(query.scope == .personal)
        #expect(query.limit == 6 && query.offset == 0)
    }

    @Test("當月淨收支來自當月的收支趨勢(依視角),分類預算帶入明確的當月")
    func monthlyQueries() async {
        let model = model()
        model.scope = .household

        await model.load()

        #expect(await statistics.monthlyQueries == [.init(year: 2026, scope: .household)])
        #expect(await statistics.budgetQueries == [CalendarMonth(year: 2026, month: 9)])
    }

    @Test("三張統計卡：淨可用資產、真實可支配現金、當月淨收支")
    func summaryCards() async throws {
        let model = await loaded()
        let summary = try #require(model.summary)

        #expect(summary.availableBalance == SampleAccounts.summary.availableBalance)
        #expect(summary.disposableCash == SampleAccounts.summary.disposableCash)
        #expect(model.monthIncome == Money(45000))
        #expect(model.monthExpense == Money(1250))
        #expect(model.monthNet == Money(43750))
    }

    @Test("當月沒有收支紀錄時，當月淨收支是 0")
    func noMonthlySummary() async {
        let statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 8))
        let model = OverviewModel(
            accounts: accounts, transactions: transactions, statistics: statistics, goals: goals,
            dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.monthIncome == .zero)
        #expect(model.monthExpense == .zero)
    }

    /// web 的總覽只算個人私帳(parity 刻意偏離第 9 項);iOS 的「個人」是我記的全部。
    @Test("當月淨收支的標題隨視角改變", arguments: [
        (ViewScope.all, "當月淨收支"), (.household, "當月淨收支(家庭)"), (.personal, "當月淨收支(個人)"),
    ])
    func netTitle(scope: ViewScope, expected: String) {
        let model = model()
        model.scope = scope

        #expect(model.netTitle == expected)
    }

    @Test("超支警示只列出超支的分類")
    func overBudgetAlert() async {
        let model = await loaded()

        #expect(model.overBudgets.map(\.category) == [.dining])
        #expect(model.overBudgetTitle == "有 1 個分類支出已超出預算")
    }

    @Test("儲蓄目標只顯示前 3 個")
    func topGoals() async {
        let goals = InMemorySavingsGoalRepository(goals: InMemorySavingsGoalRepository.sampleGoals + InMemorySavingsGoalRepository.sampleGoals.map {
            SavingsGoal(
                id: SavingsGoalID("more-\($0.id.rawValue)"), name: "更多\($0.name)", emoji: $0.emoji, targetAmount: $0.targetAmount,
                savedAmount: $0.savedAmount, monthlyReserve: $0.monthlyReserve, deadline: $0.deadline
            )
        })
        let model = OverviewModel(
            accounts: accounts, transactions: transactions, statistics: statistics, goals: goals,
            dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.topGoals.map(\.name) == ["沖繩旅遊", "緊急備用金", "iOS 小目標"])
    }

    /// web 固定寫「早安」(parity 刻意偏離第 21 項)。
    @Test("依裝置的當地時間問候", arguments: [
        (4, "晚安"), (5, "早安"), (11, "早安"), (12, "午安"), (17, "午安"), (18, "晚安"), (23, "晚安"),
    ])
    func greeting(hour: Int, expected: String) {
        #expect(OverviewModel.greeting(hour: hour, name: "小明") == "\(expected)，小明")
    }

    @Test("家庭財務錦囊帶入週期攤提和每月預留合計")
    func tip() async {
        let model = await loaded()

        #expect(model.tipText.contains(SampleAccounts.summary.monthlyAmortization.formatted()))
        #expect(model.tipText.contains(SampleAccounts.summary.monthlySavingsReserve.formatted()))
    }

    @Test("資料版本改變後重抓(例如從總覽記一筆之後)")
    func refreshesOnDataVersionChange() async {
        let dataVersion = DataVersion()
        let model = await loaded(dataVersion: dataVersion)
        let fetches = await transactions.queries.count

        await model.refreshIfStale()
        #expect(await transactions.queries.count == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await transactions.queries.count > fetches)
    }
}
