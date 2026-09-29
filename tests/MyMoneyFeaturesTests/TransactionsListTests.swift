import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("交易頁(列表)")
struct TransactionsListTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func model(
        _ repository: InMemoryTransactionRepository,
        dataVersion: DataVersion = DataVersion()
    ) -> TransactionsModel {
        TransactionsModel(repository: repository, dataVersion: dataVersion, today: { today })
    }

    @Test("預設顯示本月 1 號到今天(台灣時間)、視角是全部")
    func defaultPeriodAndScope() {
        let list = model(InMemoryTransactionRepository(transactions: []))

        #expect(list.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(list.to == today)
        #expect(list.scope == .all)
    }

    @Test("用起迄日與視角查詢")
    func queriesWithPeriodAndScope() async {
        let repository = InMemoryTransactionRepository(transactions: [])
        let list = model(repository)
        list.scope = .personal

        await list.load()

        let query = await repository.queries.last
        #expect(query?.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(query?.to == today)
        #expect(query?.scope == .personal)
    }

    @Test("依日期分組，新的在前;每組有當日的收入與支出")
    func groupsByDate() async throws {
        let list = model(InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)))

        await list.load()

        #expect(list.days.map(\.date) == [
            CalendarDay(year: 2026, month: 9, day: 28),
            CalendarDay(year: 2026, month: 9, day: 10),
            CalendarDay(year: 2026, month: 9, day: 1),
        ])
        try #require(list.days.count == 3)
        #expect(list.days[0].expense == Money(1000))
        #expect(list.days[0].income == Money(0))
        #expect(list.days[2].income == Money(45000))
    }

    /// 信用卡扣款還款時錢只是從銀行存款帳戶移到信用卡帳戶，算進總支出會跟刷卡重複(parity 刻意偏離第 26 項)。
    @Test("加總列：筆數、總收入、總支出(不含信用卡還款)、淨收支")
    func totalsExcludeCreditCardRepayment() async {
        let list = model(InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)))

        await list.load()

        #expect(list.count == 4)
        #expect(list.totalIncome == Money(45000))
        #expect(list.totalExpense == Money(1000))
        #expect(list.net == Money(44000))
    }

    /// 轉帳、ATM 提款和報銷都各產生一筆支出和一筆收入(或其中一邊),只是資金調度;算進合計會重複(web 仍然算進去，#43)。
    @Test("加總列不含 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷),收入和支出都不算")
    func totalsExcludeAllSystemCategories() async {
        let systemRecords = [
            systemRecord("atm-out", .expense, .atmWithdrawal, Money(500)),
            systemRecord("atm-in", .income, .atmWithdrawal, Money(500)),
            systemRecord("transfer-out", .expense, .internalTransfer, Money(2000)),
            systemRecord("reimbursement-in", .income, .advanceReimbursement, Money(300)),
        ]
        let list = model(InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today) + systemRecords))

        await list.load()

        #expect(list.totalIncome == Money(45000))
        #expect(list.totalExpense == Money(1000))
        #expect(systemRecords.allSatisfy { !list.canModify($0) })
    }

    private func systemRecord(_ id: String, _ type: TransactionType, _ category: TransactionCategory, _ amount: Money) -> Transaction {
        Transaction(
            id: TransactionID(id), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
            type: type, category: category, amount: amount, note: "", date: today, isShared: false,
            recorderName: "小明"
        )
    }

    @Test("沒有符合條件的交易記錄時是空的")
    func emptyPeriod() async {
        let list = model(InMemoryTransactionRepository(transactions: []))

        await list.load()

        #expect(list.phase == .loaded)
        #expect(list.days.isEmpty)
        #expect(list.count == 0)
    }

    @Test("資料版本改變後重抓")
    func refreshesWhenDataVersionChanges() async {
        let repository = InMemoryTransactionRepository(transactions: [])
        let dataVersion = DataVersion()
        let list = model(repository, dataVersion: dataVersion)
        await list.load()
        let queriesAfterLoad = await repository.queries.count

        await list.refreshIfStale()
        #expect(await repository.queries.count == queriesAfterLoad)

        dataVersion.bump()
        await list.refreshIfStale()
        #expect(await repository.queries.count > queriesAfterLoad)
    }

    @Test("載入失敗時顯示後端的訊息")
    func loadFailure() async {
        let repository = InMemoryTransactionRepository(transactions: [])
        await repository.fail(with: .rejected("Token 無效或已過期"))
        let list = model(repository)

        await list.load()

        #expect(list.phase == .failed("Token 無效或已過期"))
    }
}
