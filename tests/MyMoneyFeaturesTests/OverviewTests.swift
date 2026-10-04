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
            dataVersion: dataVersion, defaults: defaults, today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private func loaded(dataVersion: DataVersion = DataVersion()) async -> OverviewModel {
        let model = model(dataVersion: dataVersion)
        await model.load()
        return model
    }

    /// 例如記了一筆信用卡支出，總覽還沒重新載入完就點進帳戶一覽的信用卡(code review)。
    @Test("總覽的資料比目前的資料版本舊時，打開的信用卡詳細頁會重新取得")
    func cardDetailFromStaleOverviewRefreshes() async throws {
        let dataVersion = DataVersion()
        let overview = await loaded(dataVersion: dataVersion)
        dataVersion.bump()
        let fetchesBefore = await accounts.fetchCount

        let detail = overview.makeCardDetail(for: try #require(overview.creditCards.first))
        await detail.refreshIfStale()

        #expect(await accounts.fetchCount == fetchesBefore + 1)
    }

    @Test("帳戶一覽列出現金")
    func accountsListIncludesCash() async {
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sampleWithCash(), transactions: transactions, statistics: statistics,
            goals: goals, dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.cashWallets.map(\.name) == ["iOS 測試皮夾"])
    }

    @Test("視角也套用在資金指標和帳戶一覽(web 的 Dashboard 在 82d9124 起帶同一個 scope)", arguments: [
        (ViewScope.all, AccountScope.all), (.household, .household), (.personal, .personal),
    ])
    func scopeAppliesToBalanceAndAccounts(scope: ViewScope, accountScope: AccountScope) async {
        let model = model()
        model.scope = scope

        await model.load()

        #expect(await accounts.requestedScopes.last == accountScope)
        #expect(await accounts.requestedSummaryScopes.last == accountScope)
    }

    @Test("帳戶一覽沒有帳戶時，依範圍顯示空狀態的標題與說明(web 的 Dashboard)", arguments: [
        (AccountScope.all, "尚未建立帳戶", "至帳戶管理新增你的活存帳戶、現金或信用卡"),
        (.household, "目前無家庭公帳帳戶", "至帳戶管理將帳戶歸屬設為家庭公帳即可在此呈現"),
        (.personal, "目前無個人私帳帳戶", "至帳戶管理新增你的活存帳戶、現金或信用卡"),
    ])
    func emptyAccountsState(scope: AccountScope, title: String, hint: String) {
        #expect(scope.emptyAccountsTitle == title)
        #expect(scope.emptyAccountsHint == hint)
    }

    @Test("重新載入(切換視角、資料版本改變)期間維持已載入的內容，不回到骨架屏(web 的二度篩選過渡)", .timeLimit(.minutes(1)))
    func reloadKeepsLoadedContent() async {
        let gate = Gate()
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sampleWithCash(gate: gate), transactions: transactions, statistics: statistics,
            goals: goals, dataVersion: DataVersion(), defaults: defaults, today: { today }
        )
        await gate.open()
        await model.load()
        #expect(model.phase == .loaded)

        await gate.close()
        model.scope = .household
        let reloading = Task { await model.load() }
        await gate.waitUntilReached()
        #expect(model.phase == .loaded)
        #expect(model.cashWallets.map(\.name) == ["iOS 測試皮夾"])
        await gate.open()
        await reloading.value
    }

    @Test("視角預設全部;選過的視角記在 UserDefaults,下次打開沿用")
    func scopeIsRemembered() {
        let first = model()
        #expect(first.scope == .all)

        first.scope = .household

        #expect(model().scope == .household)
    }

    @Test("最近 5 筆收支明細不限日期，依目前的視角查詢")
    func recentTransactionsQuery() async throws {
        let model = model()
        model.scope = .personal

        await model.load()

        let query = try #require(await transactions.queries.last)
        #expect(query.from == nil && query.to == nil)
        #expect(query.scope == .personal)
        #expect(query.limit == 5 && query.offset == 0)
    }

    @Test("當月淨收支來自當月的收支趨勢(依視角),預算額度帶入明確的當月")
    func monthlyQueries() async {
        let model = model()
        model.scope = .household

        await model.load()

        #expect(await statistics.monthlyQueries == [.init(year: 2026, scope: .household)])
        #expect(await statistics.budgetQueries == [CalendarMonth(year: 2026, month: 9)])
    }

    @Test("摘要：淨可用餘額(主數字)、真實可支配現金、當月淨收支")
    func summaryNumbers() async throws {
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
        (ViewScope.all, "當月淨收支"), (.household, "當月淨收支(家庭公帳)"), (.personal, "當月淨收支(個人私帳)"),
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

    /// 超支警告每個超支的分類一列(#75):分類名稱和超支金額(已花減預算額度),順序跟後端一樣;沒超支的分類不列。
    @Test("超支警告每個超支的分類一列，顯示分類名稱和超支金額")
    func overBudgetRows() async {
        let transport = TransactionCategory("交通")
        let statistics = InMemoryStatisticsRepository(
            expensesByScope: [:], summaries: [], shares: [],
            budgets: [
                Budget(category: .dining, amount: Money(100), spent: Money(120), isOver: true),
                Budget(category: TransactionCategory("購物"), amount: Money(1000), spent: Money(880), isOver: false),
                Budget(category: transport, amount: Money(500), spent: Money(1250), isOver: true),
            ]
        )
        let model = OverviewModel(
            accounts: accounts, transactions: transactions, statistics: statistics, goals: goals,
            dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.overBudgets == [
            OverBudget(category: .dining, overspent: Money(20)),
            OverBudget(category: transport, overspent: Money(750)),
        ])
        #expect(model.overBudgets.map(\.category.name) == ["餐飲", "交通"])
        #expect(model.overBudgetTitle == "有 2 個分類支出已超出預算")
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

    /// 畫面用 `refreshIfStale()`:從信用卡詳細頁返回時不重抓，換了視角才重抓(code review)。
    @Test("視角改變後重抓")
    func refreshesOnScopeChange() async {
        let model = await loaded()
        let fetches = await transactions.queries.count

        model.scope = .household
        await model.refreshIfStale()

        #expect(await transactions.queries.last?.scope == .household)
        #expect(await transactions.queries.count > fetches)
    }
}

@Suite("帳戶檢視範圍的名稱(CONTEXT.md「帳戶歸屬」)")
struct AccountScopeTitleTests {
    @Test("帳戶檢視範圍是「全部」「公帳」「私帳」(上游 ADR 0014，#138)")
    func titles() {
        #expect(AccountScope.allCases.map(\.title) == ["全部", "家庭公帳", "個人私帳"])
    }
}
