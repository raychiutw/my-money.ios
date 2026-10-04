import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽:淨可用餘額的組成、數字磚的明細與功能入口格(#178)")
struct OverviewEntriesTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    init() {
        let suite = "OverviewEntriesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    /// 後端算好的資金指標:現金 1,500、活存帳戶 50,000、待繳 20,000 + 8,500、週期支出每月平均 14,000、每月預留 5,200。
    private var summary: BalanceSummary {
        BalanceSummary(
            cashTotal: Money(1500), bankBalanceTotal: Money(50000), billedDebtTotal: Money(20000), unbilledDebtTotal: Money(8500),
            availableBalance: Money(23000), monthlyAmortization: Money(14000), monthlySavingsReserve: Money(5200),
            disposableCash: Money(3800)
        )
    }

    private struct Sources {
        var accounts: InMemoryAccountRepository
        var transactions: InMemoryTransactionRepository
        var statistics: InMemoryStatisticsRepository
        var goals: InMemorySavingsGoalRepository
        var forecast: InMemoryForecastRepository?
    }

    private func sources() -> Sources {
        Sources(
            accounts: InMemoryAccountRepository(accounts: [.cash(SampleAccounts.wallet)] + SampleAccounts.all, summary: summary),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: .sample(),
            forecast: .sample(today: today)
        )
    }

    private func model(_ sources: Sources) -> OverviewModel {
        OverviewModel(
            accounts: sources.accounts, transactions: sources.transactions, statistics: sources.statistics, goals: sources.goals,
            forecast: sources.forecast, dataVersion: DataVersion(), defaults: defaults, today: { today },
            locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private func loaded(_ sources: Sources? = nil) async -> OverviewModel {
        let overview = model(sources ?? self.sources())
        await overview.load()
        return overview
    }

    private func entry(_ destination: OverviewEntry.Destination, in overview: OverviewModel) throws -> OverviewEntry {
        try #require(overview.entries.first { $0.destination == destination })
    }

    // MARK: 淨可用餘額的組成

    @Test("淨可用餘額底下一行組成:現金＋活存帳戶−信用卡待繳,全是後端的值;載入前沒有")
    func composition() async {
        let overview = model(sources())
        #expect(overview.compositionText == nil)

        await overview.load()

        #expect(overview.compositionText == "現金 $1,500 ＋ 活存帳戶 $50,000 − 信用卡待繳 $28,500")
        #expect(overview.compositionSpokenText == "現金 1,500 元，加活存帳戶 50,000 元，減信用卡待繳 28,500 元")
        #expect(overview.compositionParts == ["現金 $1,500", "＋ 活存帳戶 $50,000", "− 信用卡待繳 $28,500"], "放不下時一段一行")
    }

    // MARK: 數字磚的兩行明細

    @Test("可支配現金:每月平均與每月預留;當月淨收支:收入與支出;信用卡待繳:張數與最近的繳款日")
    func tileDetails() async {
        let overview = await loaded()

        let tiles = overview.summaryTiles
        #expect(tiles.map(\.details) == [
            ["每月平均 $14,000", "每月預留 $5,200"],
            ["收入 +$45,000", "支出 −$1,250"],
            ["2 張卡", "最近 5 日繳"],
        ])
        #expect(tiles.map(\.spokenDetails) == [
            "\(Terms.expenseAmortization) 14,000 元，每月預留 5,200 元",
            "收入 45,000 元，支出 1,250 元",
            "2 張信用卡，最近 5 日繳款",
        ])
    }

    @Test("最近的繳款日從今天算起:今天(含)以後最小的那一天;都過了就是下個月最小的那一天")
    func nearestDueDay() async {
        let overview = model(sources())
        // 今天是 28 號:繳款日 5 與 20 都過了，下個月的 5 日最近。
        await overview.load()
        #expect(overview.summaryTiles[2].details.last == "最近 5 日繳")

        // 換成 6 號:5 日過了、20 日最近。
        let source = sources()
        let early = OverviewModel(
            accounts: source.accounts, transactions: source.transactions, statistics: source.statistics, goals: source.goals,
            dataVersion: DataVersion(), defaults: defaults, today: { CalendarDay(year: 2026, month: 9, day: 6) },
            locale: Locale(identifier: "zh_Hant_TW")
        )
        await early.load()
        #expect(early.summaryTiles[2].details.last == "最近 20 日繳")
    }

    @Test("沒有信用卡時:信用卡待繳磚寫「沒有信用卡」，沒有繳款日那行;沒有設定繳款日只寫張數")
    func tileDetailsWithoutCards() async {
        var empty = sources()
        empty.accounts = InMemoryAccountRepository(accounts: [.bank(SampleAccounts.savings)], summary: .zero)
        let overview = await loaded(empty)
        #expect(overview.summaryTiles[2].details == ["沒有信用卡"])

        var noDueDay = sources()
        let card = CreditCard(
            id: AccountID("no-due-day"), name: "沒有繳款日", colorHex: "#FFD4A0", billedDebt: Money(100), unbilledDebt: .zero,
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )
        noDueDay.accounts = InMemoryAccountRepository(accounts: [.creditCard(card)], summary: summary)
        let withoutDay = await loaded(noDueDay)
        #expect(withoutDay.summaryTiles[2].details == ["1 張卡"])
    }

    // MARK: 功能入口

    @Test("入口共 8 格,順序:記帳、帳戶、信用卡、家庭、統計、週期收支、儲蓄目標、現金流預測")
    func entryOrder() async {
        let overview = await loaded()

        #expect(overview.entries.map(\.destination) == [
            .ledger, .accounts, .creditCards, .household, .statistics, .recurring, .goals, .forecast,
        ])
        #expect(overview.entries.map(\.title) == [
            Terms.ledger, "帳戶", "信用卡", "家庭", "統計", "週期收支", "儲蓄目標", "現金流預測",
        ])
        #expect(Set(overview.entries.map(\.symbolName)).count == 8, "每個入口一個不同的圖示")
    }

    @Test("每格一個關鍵數字,都來自既有的後端值")
    func entryValues() async {
        let overview = await loaded()

        #expect(overview.entries.map(\.value) == [
            "本月 4 筆",
            "4 個帳戶",
            "待繳 $28,500",
            "小美轉給小明 $1,000",
            "9 月支出 $1,250",
            "每月平均 $14,000",
            "已存 $4,000・2.5%",
            "最低 $53,440・10月5日",
        ])
    }

    @Test("VoiceOver 念「名稱,關鍵數字」,金額念成「X 元」;沒有數字時只念名稱")
    func entrySpokenText() async throws {
        let overview = await loaded()

        #expect(try entry(.ledger, in: overview).spokenText == "\(Terms.ledger)，本月 4 筆")
        #expect(try entry(.creditCards, in: overview).spokenText == "信用卡，待繳 28,500 元")
        #expect(try entry(.household, in: overview).spokenText == "家庭，小美轉給小明 1,000 元")
        #expect(try entry(.recurring, in: overview).spokenText == "週期收支，\(Terms.expenseAmortization) 14,000 元")
        #expect(try entry(.forecast, in: overview).spokenText == "現金流預測，最低 53,440 元，10月5日")

        var missing = sources()
        missing.forecast = nil
        let withoutForecast = await loaded(missing)
        #expect(try entry(.forecast, in: withoutForecast).spokenText == "現金流預測")
    }

    @Test("警示色:信用卡有待繳時;預測會透支時。沒有待繳、不會透支就是一般色")
    func entryWarnings() async throws {
        let overview = await loaded()
        #expect(try entry(.creditCards, in: overview).isWarning)
        #expect(try !entry(.forecast, in: overview).isWarning)
        #expect(try !entry(.ledger, in: overview).isWarning)

        var calm = sources()
        calm.accounts = InMemoryAccountRepository(accounts: SampleAccounts.all, summary: .zero)
        let noDue = await loaded(calm)
        #expect(try entry(.creditCards, in: noDue).value == "待繳 $0")
        #expect(try !entry(.creditCards, in: noDue).isWarning)

        // 後端判斷會透支(最低餘額低於 0)的預測。
        let negative = CashFlowForecast(
            dailyBalances: [DailyBalance(date: today, balance: Money(-15000))], minBalance: Money(-15000),
            minDate: CalendarDay(year: 2026, month: 10, day: 11), willOverdraft: true, events: []
        )
        var custom = sources()
        custom.forecast = InMemoryForecastRepository(forecast: negative) { amount in
            PurchaseCheck(amount: amount, verdict: .danger, minBalance: .zero, affectedGoalNames: [])
        }
        let overdrawn = await loaded(custom)
        let forecast = try entry(.forecast, in: overdrawn)
        #expect(forecast.isWarning)
        #expect(forecast.value == "最低 -$15,000・10月11日")
    }

    // MARK: 每一項獨立失敗

    @Test("記帳的本月筆數載入失敗:只有那一格沒有數字,首頁其餘照常")
    func ledgerFailure() async throws {
        let failing = sources()
        await failing.transactions.fail(with: .rejected("壞了"))
        let overview = await loaded(failing)

        #expect(overview.phase == .loaded)
        #expect(try entry(.ledger, in: overview).value == nil)
        #expect(try entry(.creditCards, in: overview).value == "待繳 $28,500")
        #expect(try entry(.goals, in: overview).value == "已存 $4,000・2.5%")
    }

    @Test("儲蓄目標載入失敗:只有那一格沒有數字")
    func goalsFailure() async throws {
        let failing = sources()
        await failing.goals.fail(with: .rejected("壞了"))
        let overview = await loaded(failing)

        #expect(overview.phase == .loaded)
        #expect(try entry(.goals, in: overview).value == nil)
        #expect(try entry(.ledger, in: overview).value == "本月 4 筆")
        #expect(try entry(.forecast, in: overview).value != nil)
    }

    @Test("預測載入失敗:只有那一格沒有數字(走勢圖也沒有)")
    func forecastFailure() async throws {
        let failing = sources()
        await failing.forecast?.fail(with: .rejected("壞了"))
        let overview = await loaded(failing)

        #expect(overview.phase == .loaded)
        #expect(try entry(.forecast, in: overview).value == nil)
        #expect(overview.forecastTrend == nil)
        #expect(try entry(.statistics, in: overview).value == "9 月支出 $1,250")
    }

    @Test("家庭的公帳代墊載入失敗:只有那一格沒有數字")
    func householdFailure() async throws {
        let failing = sources()
        await failing.statistics.failHouseholdShares(with: .rejected("壞了"))
        let overview = await loaded(failing)

        #expect(overview.phase == .loaded)
        #expect(try entry(.household, in: overview).value == nil)
        #expect(try entry(.statistics, in: overview).value == "9 月支出 $1,250")
    }

    // MARK: 家庭入口的數字

    @Test("家庭:兩位成員代墊一樣多時寫「兩人一樣多」;不是剛好兩位成員、或視角是個人私帳時沒有數字")
    func householdValueCases() async throws {
        var even = sources()
        even.statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(today), shares: [
            HouseholdShare(userID: UserID("a"), userName: "小明", total: Money(5000)),
            HouseholdShare(userID: UserID("b"), userName: "小美", total: Money(5000)),
        ])
        #expect(try entry(.household, in: await loaded(even)).value == "兩人一樣多")

        var alone = sources()
        alone.statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(today), shares: [])
        #expect(try entry(.household, in: await loaded(alone)).value == nil)

        let personal = model(sources())
        personal.scope = .personal
        await personal.load()
        #expect(try entry(.household, in: personal).value == nil)
    }

    @Test("儲蓄目標還沒有任何目標時寫「尚無目標」")
    func noGoals() async throws {
        var none = sources()
        none.goals = InMemorySavingsGoalRepository(goals: [])
        #expect(try entry(.goals, in: await loaded(none)).value == "尚無目標")
    }

    // MARK: 本月筆數的查詢

    @Test("本月筆數:查本月 1 號到今天、依目前的視角、不限帳戶")
    func ledgerQuery() async {
        let source = sources()
        let overview = model(source)
        overview.scope = .household

        await overview.load()

        let queries = await source.transactions.queries
        #expect(queries.contains { $0.from == CalendarDay(year: 2026, month: 9, day: 1) && $0.to == today && $0.scope == .household })
        #expect(queries.allSatisfy { $0.accountID == nil })
    }
}
