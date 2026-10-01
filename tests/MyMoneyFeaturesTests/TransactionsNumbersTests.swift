import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("交易頁數字優先:當日淨額、支出佔收入的比例條、每日支出長條圖(#118)")
struct TransactionsNumbersTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let locale = Locale(identifier: "zh_Hant_TW")

    private func loaded(_ transactions: [MyMoneyDomain.Transaction]? = nil) async -> TransactionsModel {
        let list = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: transactions ?? SampleTransactions.make(today: today)),
            dataVersion: DataVersion(), locale: locale, today: { today }
        )
        await list.load()
        return list
    }

    // MARK: 日標頭的當日淨額

    @Test("日標頭顯示當日淨額:收入減支出，帶正負號;信用卡還款等系統分類不算")
    func dayNet() async throws {
        let list = await loaded()
        try #require(list.days.count == 3)

        // 9/28:午餐 120 + 耳機 880。
        #expect(list.days[0].net == Money(-1000))
        #expect(list.days[0].netText == "-$1,000")
        // 9/1:薪資 45,000。
        #expect(list.days[2].net == Money(45000))
        #expect(list.days[2].netText == "+$45,000")
        // 9/10:只有一筆信用卡還款(系統分類)，沒有淨額可以顯示。
        #expect(!list.days[1].hasNet)
    }

    // MARK: 比例條

    @Test("支出佔收入的比例:總支出除以總收入(都不含系統分類);收入是 0 時沒有比例條")
    func expenseRatio() async throws {
        let list = await loaded()

        // 支出 1,000 / 收入 45,000。
        let ratio = try #require(list.expenseRatio)
        #expect(abs(ratio - 1000.0 / 45000.0) < 0.0001)
        #expect(list.expenseRatioSummary == "支出佔收入百分之 2")

        // 只看支出:收入是 0，沒有比例條。
        list.editFilter()
        list.filterDraft.type = .expense
        await list.applyFilter()
        #expect(list.totalIncome == .zero)
        #expect(list.expenseRatio == nil)
        #expect(list.expenseRatioSummary == nil)
    }

    @Test("支出超過收入時比例超過 100%，VoiceOver 照實念出")
    func expenseRatioOverOneHundredPercent() async {
        let list = await loaded(
            [
                transaction("income", .income, 1000, on: today.firstOfMonth),
                transaction("expense", .expense, 2500, on: today),
            ]
        )

        #expect(list.expenseRatio == 2.5)
        #expect(list.expenseRatioSummary == "支出佔收入百分之 250")
    }

    // MARK: 每日支出長條圖

    @Test("每日支出涵蓋篩選區間的每一天(沒花錢的天是 0)，只算支出、不含系統分類")
    func dailyExpensesCoverTheRange() async {
        let list = await loaded()

        let days = list.dailyExpenses
        #expect(days.count == 28)
        #expect(days.first?.date == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(days.last?.date == today)
        #expect(days.last?.amount == Money(1000))
        // 9/10 只有信用卡還款(系統分類)，不算支出;9/1 的收入也不算。
        #expect(days.filter { $0.amount > .zero }.map(\.date) == [today])
    }

    @Test("突顯最大的一天:最大的一天標記為 peak，金額相同時取較早的一天")
    func peakDay() async throws {
        let list = await loaded(
            [
                transaction("a", .expense, 300, on: CalendarDay(year: 2026, month: 9, day: 5)),
                transaction("b", .expense, 300, on: CalendarDay(year: 2026, month: 9, day: 20)),
                transaction("c", .expense, 100, on: CalendarDay(year: 2026, month: 9, day: 6)),
            ]
        )

        let peak = try #require(list.dailyExpenses.first { $0.isPeak })
        #expect(peak.date == CalendarDay(year: 2026, month: 9, day: 5))
        #expect(list.dailyExpenses.filter(\.isPeak).count == 1)
        #expect(list.dailyExpenseSummary == "本區間每日支出，最多的一天是9月5日，支出 300 元")
    }

    @Test("整個區間都沒有支出時沒有最大的一天，也沒有長條圖")
    func noExpensesNoPeak() async {
        let list = await loaded([transaction("income", .income, 1000, on: today)])

        #expect(list.dailyExpenses.allSatisfy { $0.amount == .zero && !$0.isPeak })
        #expect(!list.hasDailyExpenses)
        #expect(list.dailyExpenseSummary == nil)
    }

    @Test("長條圖跟著篩選:只看某個分類時只算那個分類的支出")
    func dailyExpensesFollowTheFilter() async {
        let list = await loaded()
        list.editFilter()
        list.filterDraft.category = .dining
        await list.applyFilter()

        #expect(list.dailyExpenses.last?.amount == Money(120))
    }

    @Test("區間兩端的日期標籤:系統格式")
    func rangeLabels() async {
        let list = await loaded()

        #expect(list.rangeStartText == "9月1日")
        #expect(list.rangeEndText == "9月28日")
    }

    private func transaction(_ id: String, _ type: TransactionType, _ amount: Int, on date: CalendarDay) -> MyMoneyDomain.Transaction {
        MyMoneyDomain.Transaction(
            id: TransactionID(id), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: type,
            category: type == .income ? .salary : .dining, amount: Money(Decimal(amount)), note: id, date: date, isShared: true,
            recorderName: "小明"
        )
    }
}
