import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽下半部:數字磚、帳戶卡片、超支提示、儲蓄目標圓環(#117)")
struct OverviewLowerTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    init() {
        let suite = "OverviewLowerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(accounts: InMemoryAccountRepository, goals: InMemorySavingsGoalRepository = .sample()) -> OverviewModel {
        OverviewModel(
            accounts: accounts,
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: goals,
            dataVersion: DataVersion(), defaults: defaults, today: { today }, locale: Locale(identifier: "zh_Hant_TW")
        )
    }

    private func loaded(accounts: InMemoryAccountRepository = .sampleWithCash()) async -> OverviewModel {
        let overview = model(accounts: accounts)
        await overview.load()
        return overview
    }

    private func wallet(_ index: Int) -> Account {
        .cash(CashWallet(id: AccountID("w\(index)"), name: "錢包\(index)", colorHex: "#10B981", balance: Money(Decimal(100 * index)), isJointFund: false))
    }

    private func bank(_ index: Int) -> Account {
        .bank(BankAccount(id: AccountID("b\(index)"), name: "銀行\(index)", colorHex: "#A8D8EA", balance: Money(Decimal(1000 * index)), isJointFund: false))
    }

    private func card(_ index: Int, billed: Int, unbilled: Int = 0, dueDay: Int? = 5) -> Account {
        .creditCard(
            CreditCard(
                id: AccountID("c\(index)"), name: "信用卡\(index)", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)),
                unbilledDebt: Money(Decimal(unbilled)), creditLimit: nil, statementDay: nil, paymentDueDay: dueDay
            )
        )
    }

    // MARK: 數字磚

    @Test("信用卡待繳磚:後端的已出帳待繳款加未出帳款合計，載入前沒有值")
    func cardDueTile() async {
        let overview = model(accounts: .sampleWithCash())
        #expect(overview.totalCardDue == nil)

        await overview.load()

        #expect(overview.totalCardDue == Money(28500))
    }

    // MARK: 數字磚的標籤(#127)

    @Test("三格數字磚:畫面用簡稱(可支配現金、當月淨收支、信用卡待繳)，VoiceOver 念正名與完整金額")
    func tileTitles() async throws {
        let overview = await loaded()

        let tiles = overview.summaryTiles
        #expect(tiles.map(\.title) == ["可支配現金", "當月淨收支", "信用卡待繳"])
        #expect(tiles.map(\.spokenTitle) == ["真實可支配現金", "當月淨收支", "信用卡待繳"])
        #expect(tiles.map(\.amount) == [Money(23000), overview.monthNet, Money(28500)])
    }

    @Test("視角不是全部時，視角寫在 VoiceOver 的標籤，畫面上的標籤不加(才不會被截斷)")
    func scopeIsOnlySpoken() async throws {
        let overview = model(accounts: .sampleWithCash())
        overview.scope = .household
        await overview.load()

        let net = try #require(overview.summaryTiles.dropFirst().first)
        #expect(net.title == "當月淨收支")
        #expect(net.spokenTitle == "當月淨收支(家庭公帳)")
    }

    @Test("警示色:可支配現金與當月淨收支是負數時、信用卡待繳大於 0 時")
    func tileWarnings() async throws {
        let negative = BalanceSummary(
            cashTotal: .zero, bankBalanceTotal: Money(1000), billedDebtTotal: Money(500), unbilledDebtTotal: .zero,
            availableBalance: Money(500), monthlyAmortization: .zero, monthlySavingsReserve: .zero, disposableCash: Money(-97799)
        )
        let overview = await loaded(accounts: InMemoryAccountRepository(accounts: [], summary: negative))

        let flags = overview.summaryTiles.map(\.isWarning)
        // 可支配現金 -97,799 是負數;當月淨收支是來自範例交易的 +44,000;信用卡待繳 500 大於 0。
        #expect(flags == [true, false, true])
        let settled = await loaded(accounts: InMemoryAccountRepository(accounts: [], summary: .zero))
        #expect(settled.summaryTiles.map(\.isWarning) == [false, false, false])
    }

    // MARK: 帳戶卡片

    @Test("帳戶卡片的順序跟帳戶頁一樣:現金、活存帳戶、信用卡;每張卡是名稱加大金額，信用卡的金額是信用卡待繳總額")
    func accountCardOrderAndAmounts() async {
        let overview = await loaded()

        #expect(overview.accountCards.map(\.name) == ["iOS 測試皮夾", "iOS 測試存款", "iOS 測試信用卡", "iOS 測試小額卡"])
        #expect(overview.accountCards.map(\.amount) == [Money(1500), Money(50000), Money(15500), Money(13000)])
        #expect(overview.accountCards.map(\.isCreditCard) == [false, false, true, true])
    }

    @Test("信用卡卡片:有待繳時是警示狀態，視覺「N 日繳」、VoiceOver「每月 N 日繳款」;沒有設定繳款日時不顯示")
    func creditCardCardDueDay() async throws {
        let repository = InMemoryAccountRepository(
            accounts: [card(1, billed: 1000, dueDay: 5), card(2, billed: 0, dueDay: nil), card(3, billed: 0, dueDay: 20)],
            summary: SampleAccounts.summary
        )
        let overview = await loaded(accounts: repository)
        let (due, noDay, settled) = (overview.accountCards[0], overview.accountCards[1], overview.accountCards[2])

        #expect(due.isDue)
        #expect(due.dueDayText == "5 日繳")
        #expect(due.spokenText == "信用卡1，信用卡待繳總額 1,000 元，每月 5 日繳款")
        #expect(noDay.dueDayText == nil)
        #expect(noDay.spokenText == "信用卡2，信用卡待繳總額 0 元")
        // 已全數結清:不是警示狀態(金額不用紅色)。
        #expect(!settled.isDue)
    }

    @Test("現金與活存帳戶卡片:VoiceOver 念名稱、類型、餘額;沒有繳款日")
    func cashAndBankCardsSpeakKindAndBalance() async throws {
        let overview = await loaded()
        let wallet = try #require(overview.accountCards.first)
        let bank = overview.accountCards[1]

        #expect(wallet.spokenText == "iOS 測試皮夾，現金，餘額 1,500 元")
        #expect(bank.spokenText == "iOS 測試存款，活存帳戶，餘額 50,000 元")
        #expect(wallet.dueDayText == nil && !wallet.isDue)
    }

    @Test("帳戶卡片最多 6 張，其餘用「管理」到帳戶頁;超過上限時依現金、銀行、信用卡的順序截斷")
    func accountCardLimit() async {
        let accounts = [wallet(1), wallet(2), wallet(3), bank(1), bank(2), bank(3), card(1, billed: 1), card(2, billed: 2), card(3, billed: 3)]
        let overview = await loaded(accounts: InMemoryAccountRepository(accounts: accounts, summary: SampleAccounts.summary))

        #expect(overview.accountCards.count == 6)
        #expect(overview.accountCards.map(\.name) == ["錢包1", "錢包2", "錢包3", "銀行1", "銀行2", "銀行3"])
        #expect(overview.hasMoreAccounts)
    }

    @Test("帳戶不超過上限時全部顯示，沒有更多")
    func noMoreAccountsWithinTheLimit() async {
        let overview = await loaded()

        #expect(overview.accountCards.count == 4)
        #expect(!overview.hasMoreAccounts)
    }

    @Test("沒有任何帳戶時沒有卡片(畫面顯示空狀態)")
    func noAccountsNoCards() async {
        let overview = await loaded(accounts: InMemoryAccountRepository(accounts: [], summary: .zero))

        #expect(overview.accountCards.isEmpty)
    }

    // MARK: 超支提示

    @Test("超支提示:精簡的「N 個分類超支」，VoiceOver 念完整的一句;沒有超支時沒有提示")
    func overBudgetChip() async {
        let overview = await loaded()

        #expect(overview.overBudgets.count == 1)
        #expect(overview.overBudgetChipTitle == "1 個分類超支")
        #expect(overview.overBudgetTitle == "有 1 個分類支出已超出預算")
    }

    // MARK: 儲蓄目標圓環

    @Test("儲蓄目標圓環最多三個，百分比來自後端的已存與目標金額;VoiceOver 念「名稱，已達成百分之 N」")
    func goalRings() async throws {
        let goals = InMemorySavingsGoalRepository(
            goals: (1...4).map {
                SavingsGoal(
                    id: SavingsGoalID("g\($0)"), name: "目標\($0)", emoji: "🎯", targetAmount: Money(1000),
                    savedAmount: Money(Decimal(100 * $0)), monthlyReserve: .zero, deadline: nil
                )
            }
        )
        let overview = model(accounts: .sampleWithCash(), goals: goals)
        await overview.load()

        #expect(overview.topGoals.count == 3)
        #expect(overview.topGoals.map(\.percentText) == ["10%", "20%", "30%"])
        #expect(overview.topGoals.map(\.ringSpokenText) == ["目標1，已達成百分之 10", "目標2，已達成百分之 20", "目標3，已達成百分之 30"])
    }

    @Test("圓環的百分比最多 100，目標金額是 0 時是 0")
    func ringPercentIsClamped() {
        let full = SavingsGoal(
            id: SavingsGoalID("full"), name: "滿了", emoji: "🎒", targetAmount: Money(1000), savedAmount: Money(1500),
            monthlyReserve: .zero, deadline: nil
        )
        let empty = SavingsGoal(
            id: SavingsGoalID("empty"), name: "空的", emoji: "🎒", targetAmount: .zero, savedAmount: .zero, monthlyReserve: .zero,
            deadline: nil
        )

        #expect(full.ringSpokenText == "滿了，已達成百分之 100")
        #expect(empty.ringSpokenText == "空的，已達成百分之 0")
    }
}
