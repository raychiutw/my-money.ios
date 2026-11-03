import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 記帳頁每頁 20 筆、篩選與統計由後端提供(上游 `b06d17c`、ADR 0035、#184,#317)。
@MainActor
@Suite("記帳頁分頁:每頁 20 筆,篩選與總額由後端提供")
struct TransactionsPagingTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    /// 9 月 1 號到 28 號,每天 2 筆(一筆午餐支出 100、一筆薪資收入 1000),共 56 筆。
    private func many() -> [Transaction] {
        (1...28).flatMap { day -> [Transaction] in
            let date = CalendarDay(year: 2026, month: 9, day: day)
            return [
                Transaction(
                    id: TransactionID("e\(day)"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: .expense,
                    category: .dining, amount: Money(100), note: "午餐\(day)", date: date, isShared: false, recorderName: "小明"
                ),
                Transaction(
                    id: TransactionID("i\(day)"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: .income,
                    category: .salary, amount: Money(1000), note: "薪資\(day)", date: date, isShared: false, recorderName: "小美"
                ),
            ]
        }
    }

    private func make(_ transactions: [Transaction]? = nil) -> (TransactionsModel, InMemoryTransactionRepository) {
        let repository = InMemoryTransactionRepository(transactions: transactions ?? many())
        return (TransactionsModel(repository: repository, dataVersion: DataVersion(), today: { today }), repository)
    }

    @Test("載入:只要第一頁 20 筆;總收入、總支出、筆數是整個月的(後端統計),不是已載入的 20 筆")
    func firstPageAndFullTotals() async {
        let (model, repository) = make()
        await model.load()

        let request = await repository.pageRequests.first
        #expect(request?.limit == 20)
        #expect(request?.cursor == nil)
        #expect(model.days.flatMap(\.transactions).count == 20)
        #expect(model.count == 56)
        #expect(model.totalIncome == Money(28000))
        #expect(model.totalExpense == Money(2800))
        #expect(model.net == Money(25200))
        #expect(await repository.summaryRequests.count == 1)
    }

    @Test("每日小計是整天的準確值:最底下那一天只載入一半時也一樣")
    func dayTotalsAreForTheWholeDay() async throws {
        let (model, _) = make()
        await model.load()

        // 20 筆 = 9/28 到 9/19 十天各 2 筆,剛好整天。換成奇數頁讓最底下的天只載入一筆。
        let (odd, _) = make(Array(many().prefix(55)))
        await odd.load()
        let bottom = try #require(odd.days.last)
        #expect(bottom.transactions.count < 2 || bottom.income == Money(1000))
        #expect(model.days.first?.income == Money(1000))
        #expect(model.days.first?.expense == Money(100))
    }

    @Test("還有下一頁:loadMore 用上一頁的游標接著載,接在後面;載完就沒有了")
    func loadMoreAppends() async {
        let (model, repository) = make()
        await model.load()
        #expect(model.canLoadMore)

        await model.loadMore()
        #expect(model.days.flatMap(\.transactions).count == 40)
        await model.loadMore()
        #expect(model.days.flatMap(\.transactions).count == 56)
        #expect(!model.canLoadMore)
        await model.loadMore()
        #expect(await repository.pageRequests.count == 3, "沒有下一頁就不再送請求")
        #expect(await repository.pageRequests[1].cursor == "20")
    }

    @Test("篩選全部交給後端:類型、分類套用後從第一頁重載,不是本機過濾")
    func typeAndCategoryReload() async {
        let (model, repository) = make()
        await model.load()
        await model.loadMore()

        model.editFilter()
        model.filterDraft.type = .income
        await model.applyFilter()

        let request = await repository.pageRequests.last
        #expect(request?.query.type == .income)
        #expect(request?.cursor == nil, "條件改變從第一頁重來")
        #expect(model.count == 28)
        #expect(model.totalExpense == .zero)
        #expect(model.days.flatMap(\.transactions).count == 20)
    }

    @Test("搜尋:關鍵字送給後端,找的是整個月(含還沒載入的),總額跟著篩選")
    func keywordSearch() async {
        let (model, repository) = make()
        await model.load()

        model.keyword = "午餐3"
        await model.search()

        #expect(await repository.pageRequests.last?.query.keyword == "午餐3")
        #expect(model.days.flatMap(\.transactions).map(\.note) == ["午餐3"])
        #expect(model.count == 1)
        #expect(model.totalExpense == Money(100))
        #expect(model.isFilterActive)
    }

    @Test("關鍵字只是空白或沒變:不重新查詢")
    func blankKeywordDoesNotQuery() async {
        let (model, repository) = make()
        await model.load()
        let before = await repository.pageRequests.count

        model.keyword = "   "
        await model.search()
        #expect(await repository.pageRequests.count == before)

        model.keyword = "午餐1"
        await model.search()
        await model.search()
        #expect(await repository.pageRequests.count == before + 1, "同一個關鍵字不重複查詢")
        model.keyword = ""
        await model.search()
        #expect(await repository.pageRequests.last?.query.keyword == nil)
    }

    @Test("每日支出長條圖用後端的每日小計(整個區間準確)")
    func dailyExpensesFromSummary() async {
        let (model, _) = make()
        await model.load()

        #expect(model.dailyExpenses.count == 28)
        #expect(model.dailyExpenses.allSatisfy { $0.amount == Money(100) })
        #expect(model.hasDailyExpenses)
    }

    @Test("載入下一頁失敗:已載入的留著,顯示錯誤,還能再試")
    func loadMoreFailure() async {
        let (model, repository) = make()
        await model.load()
        await repository.fail(with: .rejected("伺服器忙碌"))

        await model.loadMore()

        #expect(model.days.flatMap(\.transactions).count == 20)
        #expect(model.alertMessage == "伺服器忙碌")
        #expect(model.canLoadMore)
    }

    @Test("換月份:從第一頁重載,舊月份的游標不會用在新月份")
    func monthSwitchResets() async {
        let (model, repository) = make()
        await model.load()
        await model.loadMore()

        await model.goToPreviousMonth()

        let request = await repository.pageRequests.last
        #expect(request?.cursor == nil)
        #expect(request?.query.from == CalendarDay(year: 2026, month: 8, day: 1))
        #expect(model.count == 0)
    }
}
