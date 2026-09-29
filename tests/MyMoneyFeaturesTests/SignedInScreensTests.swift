import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登入後的畫面跟著 session 建立")
struct SignedInScreensTests {
    private func session(_ id: String) -> Session {
        Session(token: "token-\(id)", user: User(id: UserID(id), email: "\(id)@example.com", name: id))
    }

    private func makeScreens() -> SignedInScreens {
        SignedInScreens { user in
            MainScreens(
                currentUser: user.id,
                accountRepository: InMemoryAccountRepository.sample(),
                transactionRepository: InMemoryTransactionRepository(transactions: []),
                recurringRepository: InMemoryRecurringRepository(items: []),
                savingsGoalRepository: InMemorySavingsGoalRepository(goals: []),
                statisticsRepository: InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)),
                forecastRepository: InMemoryForecastRepository.sample(today: CalendarDay(year: 2026, month: 9, day: 28)),
                householdRepository: InMemoryHouseholdRepository(household: nil),
                botRepository: InMemoryBotRepository(bindings: [])
            )
        }
    }

    @Test("同一個人的 session 更新時，沿用同一份畫面(不重抓資料)")
    func sameUserKeepsScreens() throws {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        let first = try #require(screens.current?.accounts)

        screens.update(for: session("mei"))

        #expect(screens.current?.accounts === first)
    }

    @Test("換成另一個人登入時，建立新的畫面，不會看到上一個人的資料")
    func differentUserGetsFreshScreens() throws {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        let first = try #require(screens.current?.accounts)

        screens.update(for: nil)
        screens.update(for: session("ming"))

        #expect(screens.current != nil)
        #expect(screens.current?.accounts !== first)
    }

    /// 交易記錄列只有不是自己記的才顯示記帳人(#72),所以畫面 model 要知道登入的是誰。
    @Test("畫面 model 知道登入的是誰：自己記的交易記錄不顯示記帳人")
    func screensKnowSignedInUser() throws {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        let current = try #require(screens.current)
        let mine = Transaction(
            id: TransactionID("mine"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
            type: .expense, category: .dining, amount: Money(120), note: "", date: CalendarDay(year: 2026, month: 9, day: 28),
            isShared: true, recorderName: "mei", recorderID: UserID("mei")
        )

        #expect(current.transactions.recorderName(of: mine) == nil)
        #expect(current.overview.recorderName(of: mine) == nil)
    }

    @Test("登出時丟掉畫面")
    func signOutDropsScreens() {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        #expect(screens.current != nil)

        screens.update(for: nil)

        #expect(screens.current == nil)
    }
}
