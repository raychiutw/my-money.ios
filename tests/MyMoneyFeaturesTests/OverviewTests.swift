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

    /// 最近交易跟交易頁用同一種交易記錄列：記帳人只有不是自己記的才顯示(#72)。
    @Test("最近交易的記帳人只有不是自己記的才顯示")
    func recentRecorderOnlyForOthers() {
        let me = InMemoryAuthRepository.Member.sample.user
        let model = OverviewModel(
            accounts: accounts, transactions: transactions, statistics: statistics, goals: goals,
            dataVersion: DataVersion(), defaults: defaults, currentUser: me.id, today: { today }
        )
        func recorded(by name: String, id: UserID) -> MyMoneyDomain.Transaction {
            MyMoneyDomain.Transaction(
                id: TransactionID("recorded-by-\(id.rawValue)"), accountID: SampleAccounts.savings.id,
                accountName: SampleAccounts.savings.name, type: .expense, category: .dining, amount: Money(120),
                note: "", date: today, isShared: true, recorderName: name, recorderID: id
            )
        }

        #expect(model.recorderName(of: recorded(by: me.name, id: me.id)) == nil)
        #expect(model.recorderName(of: recorded(by: "小美", id: UserID("mei"))) == "小美")
    }

    @Test("帳戶一覽列出現金錢包;淨可用餘額的組成是現金加銀行存款減信用卡待繳總額(web 的 Dashboard 寫成「現金 + 銀行存款帳戶 - 卡債」)")
    func availableBreakdownIncludesCash() async {
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sampleWithCash(), transactions: transactions, statistics: statistics,
            goals: goals, dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        await model.load()

        #expect(model.cashWallets.map(\.name) == ["iOS 測試皮夾"])
        #expect(model.availableBreakdown == "現金 $1,500 + 銀行存款 $50,000 - 信用卡待繳總額 $28,500")
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
        (AccountScope.all, "尚未建立帳戶", "至帳戶管理新增你的銀行存款帳戶、現金錢包或信用卡"),
        (.household, "目前無家庭共同基金帳戶", "至帳戶管理將帳戶屬性設為「家庭共同基金」即可在此呈現"),
        (.personal, "目前無個人私帳", "至帳戶管理新增你的銀行存款帳戶、現金錢包或信用卡"),
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

    @Test("最近 6 筆交易記錄不限日期，依目前的視角查詢")
    func recentTransactionsQuery() async throws {
        let model = model()
        model.scope = .personal

        await model.load()

        let query = try #require(await transactions.queries.last)
        #expect(query.from == nil && query.to == nil)
        #expect(query.scope == .personal)
        #expect(query.limit == 6 && query.offset == 0)
    }

    @Test("當月淨收支來自當月的收支趨勢(依視角),預算額度帶入明確的當月")
    func monthlyQueries() async {
        let model = model()
        model.scope = .household

        await model.load()

        #expect(await statistics.monthlyQueries == [.init(year: 2026, scope: .household)])
        #expect(await statistics.budgetQueries == [CalendarMonth(year: 2026, month: 9)])
    }

    @Test("三張統計卡：淨可用餘額、真實可支配現金、當月淨收支")
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
