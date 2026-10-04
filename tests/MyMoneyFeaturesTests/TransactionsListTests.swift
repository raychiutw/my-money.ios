import Foundation
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

        #expect(list.filter.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(list.filter.to == today)
        #expect(list.filter.scope == .all)
        #expect(list.filter.type == .all)
        #expect(list.filter.category == nil)
    }

    @Test("用起迄日與視角查詢")
    func queriesWithPeriodAndScope() async {
        let repository = InMemoryTransactionRepository(transactions: [])
        let list = model(repository)
        list.editFilter()
        list.filterDraft.scope = .personal

        await list.applyFilter()

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

    /// 系統依地區的格式(DESIGN.md「日期」),不再是 web 的「09/28」(parity 刻意偏離)。起日拉到去年，跨年的標頭要有年份。
    @Test("分組標頭是「9月28日週一」這種系統格式，不是今年的加上年份")
    func dayHeaderTitles() async {
        let newYearsEve = Transaction(
            id: TransactionID("new-years-eve"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
            type: .expense, category: .dining, amount: Money(500), note: "跨年", date: CalendarDay(year: 2025, month: 12, day: 31),
            isShared: true, recorderName: "小明"
        )
        let list = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today) + [newYearsEve]),
            dataVersion: DataVersion(), locale: Locale(identifier: "zh_Hant_TW"), today: { today }
        )
        list.editFilter()
        list.filterDraft.from = CalendarDay(year: 2025, month: 12, day: 1)

        await list.applyFilter()

        #expect(list.days.map(\.title) == ["9月28日週一", "9月10日週四", "9月1日週二", "2025年12月31日週三"])
    }

    /// 信用卡扣款還款時錢只是從活存帳戶移到信用卡帳戶，算進總支出會跟刷卡重複(parity 刻意偏離第 26 項)。
    @Test("摘要：筆數、總收入、總支出(不含信用卡還款)、淨收支")
    func totalsExcludeCreditCardRepayment() async {
        let list = model(InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)))

        await list.load()

        #expect(list.count == 4)
        #expect(list.totalIncome == Money(45000))
        #expect(list.totalExpense == Money(1000))
        #expect(list.net == Money(44000))
    }

    /// 轉帳、ATM 提款和報銷都各產生一筆支出和一筆收入(或其中一邊),只是資金調度;算進合計會重複(web 仍然算進去，#43)。
    @Test("摘要不含 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷),收入和支出都不算")
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

    /// 家庭裡家人記的家庭公帳也看得到;自己記的不用再顯示自己的名字(#72)。用 ID 判斷，家人可能同名。
    @Test("記帳人只有不是自己記的才顯示")
    func recorderOnlyForOthers() {
        let me = InMemoryAuthRepository.Member.sample.user
        let list = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: []), dataVersion: DataVersion(),
            currentUser: me.id, today: { today }
        )

        #expect(list.recorderName(of: recorded(by: me.name, id: me.id)) == nil)
        #expect(list.recorderName(of: recorded(by: "小美", id: UserID("mei"))) == "小美")
        #expect(list.recorderName(of: recorded(by: me.name, id: UserID("another-ming"))) == me.name)
    }

    /// 次要文字「記帳人・歸屬」(#145):自己記的也顯示;系統產生的紀錄記帳人換成「系統紀錄」;沒有記帳人名稱時只寫歸屬。
    @Test("次要文字是「記帳人・歸屬」:家人記的、自己的公帳、自己的私帳、系統紀錄")
    func rowSubtitle() {
        let me = InMemoryAuthRepository.Member.sample.user
        let list = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: []), dataVersion: DataVersion(),
            currentUser: me.id, today: { today }
        )
        func tx(_ name: String?, _ id: UserID?, shared: Bool, category: TransactionCategory = .dining) -> Transaction {
            Transaction(
                id: TransactionID("subtitle"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
                type: .expense, category: category, amount: Money(120), note: "午餐", date: today, isShared: shared,
                recorderName: name, recorderID: id
            )
        }

        #expect(list.subtitle(of: tx("小美", UserID("mei"), shared: true)).text == "小美・家庭公帳")
        #expect(list.subtitle(of: tx(me.name, me.id, shared: true)).text == "\(me.name)・家庭公帳")
        #expect(list.subtitle(of: tx(me.name, me.id, shared: false)).text == "\(me.name)・個人私帳")
        #expect(list.subtitle(of: tx(me.name, me.id, shared: true, category: .creditCardRepayment)).text == "系統紀錄・家庭公帳")
        #expect(list.subtitle(of: tx("小美", UserID("mei"), shared: false, category: .internalTransfer)).text == "系統紀錄・個人私帳")
        #expect(list.subtitle(of: tx(nil, nil, shared: true)).text == "家庭公帳")
        // 信用卡的帳單狀態(上游 ADR 0020，#188):已出帳、延至下期寫在歸屬後面;未出帳不標。
        func card(_ billing: BillingStatus) -> Transaction {
            Transaction(
                id: TransactionID("card-\(billing)"), accountID: SampleAccounts.card.id, accountName: SampleAccounts.card.name,
                type: .expense, category: .dining, amount: Money(120), note: "刷卡", date: today, isShared: false,
                recorderName: me.name, recorderID: me.id, billing: billing
            )
        }
        #expect(list.subtitle(of: card(.billed)).text == "\(me.name)・個人私帳・已出帳")
        #expect(list.subtitle(of: card(.deferred)).text == "\(me.name)・個人私帳・延至下期")
        #expect(list.subtitle(of: card(.unbilled)).text == "\(me.name)・個人私帳")
        #expect(list.subtitle(of: card(.deferred)).billing == "延至下期")
        #expect(list.subtitle(of: card(.unbilled)).billing == nil)
        #expect(list.subtitle(of: card(.deferred)).ownership == "個人私帳", "標籤不混進歸屬，畫面截斷時歸屬與標籤保留")
        // 截斷時先截名稱、歸屬保留:畫面用 recorder 與 ownership 分開排版。
        let family = list.subtitle(of: tx("小美", UserID("mei"), shared: true))
        #expect(family.recorder == "小美")
        #expect(family.ownership == "家庭公帳")
    }

    private func recorded(by name: String, id: UserID) -> Transaction {
        Transaction(
            id: TransactionID("recorded-by-\(id.rawValue)"), accountID: SampleAccounts.savings.id,
            accountName: SampleAccounts.savings.name, type: .expense, category: .dining, amount: Money(120), note: "午餐",
            date: today, isShared: true, recorderName: name, recorderID: id
        )
    }

    @Test("沒有符合條件的收支明細時是空的")
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
