import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("交易頁年月快速切換:切換等同改篩選的起迄日，跟篩選 sheet 共用同一份狀態(#130)")
struct TransactionsMonthSwitchTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let locale = Locale(identifier: "zh_Hant_TW")

    private func model(
        today: CalendarDay? = nil, repository: InMemoryTransactionRepository? = nil
    ) -> (TransactionsModel, InMemoryTransactionRepository) {
        let day = today ?? self.today
        let repository = repository ?? InMemoryTransactionRepository(transactions: SampleTransactions.make(today: day))
        let list = TransactionsModel(repository: repository, dataVersion: DataVersion(), locale: locale, today: { day })
        return (list, repository)
    }

    @Test("預設是本月:年月是「2026年9月」，下一月停用")
    func defaultsToThisMonth() {
        let (list, _) = model()

        #expect(list.selectedMonth == CalendarMonth(year: 2026, month: 9))
        #expect(list.monthTitle == "2026年9月")
        #expect(!list.canGoToNextMonth)
    }

    @Test("上一月:該月 1 號到月底(台灣時間)，並用這個範圍重新查詢")
    func previousMonthIsTheWholeMonth() async throws {
        let (list, repository) = model()
        await list.load()

        await list.goToPreviousMonth()

        #expect(list.filter.from == CalendarDay(year: 2026, month: 8, day: 1))
        #expect(list.filter.to == CalendarDay(year: 2026, month: 8, day: 31))
        #expect(list.selectedMonth == CalendarMonth(year: 2026, month: 8))
        #expect(list.monthTitle == "2026年8月")
        #expect(list.canGoToNextMonth)
        let query = try #require(await repository.queries.last)
        #expect(query.from == CalendarDay(year: 2026, month: 8, day: 1) && query.to == CalendarDay(year: 2026, month: 8, day: 31))
    }

    @Test("切回本月:範圍是本月 1 號到今天，跟預設、「重設為本月」一樣")
    func backToThisMonthEndsToday() async {
        let (list, _) = model()
        await list.goToPreviousMonth()

        await list.goToNextMonth()

        #expect(list.filter.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(list.filter.to == today)
        #expect(!list.canGoToNextMonth)
        #expect(!list.isFilterActive)
    }

    @Test("跨年:一月的上一月是去年十二月，二月月底看閏年")
    func crossesYearAndLeapYear() async {
        let (list, _) = model(today: CalendarDay(year: 2026, month: 1, day: 15))
        await list.goToPreviousMonth()
        #expect(list.filter.from == CalendarDay(year: 2025, month: 12, day: 1))
        #expect(list.filter.to == CalendarDay(year: 2025, month: 12, day: 31))

        await list.selectMonth(CalendarMonth(year: 2024, month: 2))
        #expect(list.filter.to == CalendarDay(year: 2024, month: 2, day: 29))
        await list.selectMonth(CalendarMonth(year: 2025, month: 2))
        #expect(list.filter.to == CalendarDay(year: 2025, month: 2, day: 28))
    }

    @Test("視角、類型、分類、關鍵字切換月份後維持不變")
    func keepsTheOtherFilters() async {
        let (list, _) = model()
        list.editFilter()
        list.filterDraft.scope = .personal
        list.filterDraft.type = .expense
        list.filterDraft.category = .dining
        await list.applyFilter()
        list.keyword = "午餐"

        await list.goToPreviousMonth()

        #expect(list.filter.scope == .personal)
        #expect(list.filter.type == .expense)
        #expect(list.filter.category == .dining)
        #expect(list.keyword == "午餐")
    }

    @Test("不能切到未來的月份;選了未來的月份什麼都不變")
    func cannotGoPastThisMonth() async {
        let (list, repository) = model()
        let before = list.filter
        await list.load()
        let queries = await repository.queries.count

        await list.selectMonth(CalendarMonth(year: 2026, month: 10))
        await list.goToNextMonth()

        #expect(list.filter == before)
        #expect(await repository.queries.count == queries)
    }

    @Test("跟篩選 sheet 一致:快速切月後打開 sheet，草稿就是同一個範圍;sheet 裡「重設為本月」套用後也是本月")
    func sharesStateWithTheFilterSheet() async {
        let (list, _) = model()
        await list.goToPreviousMonth()

        list.editFilter()
        #expect(list.filterDraft == list.filter)
        list.resetFilterDraftToThisMonth()
        await list.applyFilter()

        #expect(list.selectedMonth == CalendarMonth(year: 2026, month: 9))
        #expect(!list.canGoToNextMonth)
    }

    @Test("在篩選 sheet 設了自訂範圍:不是整月，年月顯示範圍文字;上一月從迄日所在的月份往前")
    func customRange() async {
        let (list, _) = model()
        list.editFilter()
        list.filterDraft.from = CalendarDay(year: 2026, month: 9, day: 10)
        list.filterDraft.to = CalendarDay(year: 2026, month: 9, day: 20)
        await list.applyFilter()

        #expect(list.selectedMonth == nil)
        #expect(list.monthTitle == "9月10日–9月20日")
        #expect(list.isFilterActive)

        await list.goToPreviousMonth()
        #expect(list.filter.from == CalendarDay(year: 2026, month: 8, day: 1))
        #expect(list.filter.to == CalendarDay(year: 2026, month: 8, day: 31))
    }

    @Test("起日是 1 號、但迄日不是月底(或不是今天)也是自訂範圍，不是整月")
    func partialMonthIsCustom() async {
        let (list, _) = model()
        list.editFilter()
        list.filterDraft.from = CalendarDay(year: 2026, month: 8, day: 1)
        list.filterDraft.to = CalendarDay(year: 2026, month: 8, day: 20)
        await list.applyFilter()
        #expect(list.selectedMonth == nil)

        list.editFilter()
        list.filterDraft.from = CalendarDay(year: 2026, month: 9, day: 1)
        list.filterDraft.to = CalendarDay(year: 2026, month: 9, day: 20)
        await list.applyFilter()
        #expect(list.selectedMonth == nil)
    }

    @Test("非本月的整月篩選算「非預設篩選」(篩選按鈕實心)")
    func pastMonthIsAnActiveFilter() async {
        let (list, _) = model()
        #expect(!list.isFilterActive)

        await list.goToPreviousMonth()

        #expect(list.isFilterActive)
    }

    @Test("月份以台灣時間算:月初當天(10/1)本月只有一天，上一月是整個 9 月")
    func firstOfMonthInTaipei() async {
        let (list, _) = model(today: CalendarDay(year: 2026, month: 10, day: 1))
        #expect(list.filter.from == CalendarDay(year: 2026, month: 10, day: 1) && list.filter.to == CalendarDay(year: 2026, month: 10, day: 1))
        #expect(list.monthTitle == "2026年10月")

        await list.goToPreviousMonth()

        #expect(list.filter.to == CalendarDay(year: 2026, month: 9, day: 30))
    }

    @Test("切換月份後清單、淨收支、佔比、長條圖都換成該月的資料")
    func contentFollowsTheMonth() async {
        let augustSalary = MyMoneyDomain.Transaction(
            id: TransactionID("august"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: .income,
            category: .salary, amount: Money(60000), note: "", date: CalendarDay(year: 2026, month: 8, day: 5), isShared: true,
            recorderName: "小明"
        )
        let (list, _) = model(repository: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today) + [augustSalary]))
        await list.load()
        #expect(list.totalIncome == Money(45000))

        await list.goToPreviousMonth()

        #expect(list.totalIncome == Money(60000))
        #expect(list.days.map(\.date) == [CalendarDay(year: 2026, month: 8, day: 5)])
        #expect(list.dailyExpenses.count == 31)
        #expect(list.expenseRatio == 0)
    }
}
