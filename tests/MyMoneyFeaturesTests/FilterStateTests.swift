import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("篩選按鈕的「非預設篩選」狀態(#107):套用了篩選時按鈕改實心圖示")
struct FilterStateTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func list() async -> TransactionsModel {
        let repository = InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today))
        let model = TransactionsModel(repository: repository, dataVersion: DataVersion(), today: { today })
        await model.load()
        return model
    }

    @Test("交易頁:預設的篩選(全部視角、本月 1 號到今天、全部類型與分類、沒有關鍵字)不是非預設")
    func transactionsDefaultIsNotActive() async {
        #expect(await !list().isFilterActive)
    }

    @Test("交易頁:視角、起迄日、類型、分類任一個偏離預設就是非預設")
    func transactionsFilterChangesAreActive() async {
        let model = await list()

        model.editFilter()
        model.filterDraft.scope = .personal
        await model.applyFilter()
        #expect(model.isFilterActive, "視角不是全部")

        model.editFilter()
        model.filterDraft.scope = .all
        await model.applyFilter()
        #expect(!model.isFilterActive, "改回全部之後應該回到預設")

        model.editFilter()
        model.filterDraft.to = CalendarDay(year: 2026, month: 9, day: 30)
        await model.applyFilter()
        #expect(model.isFilterActive, "迄日不是今天")

        model.editFilter()
        model.resetFilterDraftToThisMonth()
        await model.applyFilter()
        #expect(!model.isFilterActive, "重設為本月之後應該回到預設")

        model.editFilter()
        model.filterDraft.from = CalendarDay(year: 2026, month: 9, day: 10)
        await model.applyFilter()
        #expect(model.isFilterActive, "起日不是本月 1 號")

        model.editFilter()
        model.resetFilterDraftToThisMonth()
        model.filterDraft.type = .expense
        await model.applyFilter()
        #expect(model.isFilterActive, "類型不是全部")

        model.editFilter()
        model.filterDraft.type = .all
        model.filterDraft.category = .dining
        await model.applyFilter()
        #expect(model.isFilterActive, "分類不是全部")
    }

    @Test("交易頁:搜尋關鍵字非空白算非預設，只有空白不算")
    func transactionsKeywordIsActive() async {
        let model = await list()

        model.keyword = "午餐"
        #expect(model.isFilterActive)

        model.keyword = "   "
        #expect(!model.isFilterActive)

        model.keyword = ""
        #expect(!model.isFilterActive)
    }

    @Test("總覽、統計的視角與帳戶頁的檢視範圍:只有「全部」是預設", arguments: [
        (ViewScope.all, true), (.household, false), (.personal, false),
    ])
    func viewScopeDefault(scope: ViewScope, isDefault: Bool) {
        #expect(scope.isDefaultFilter == isDefault)
    }

    @Test("帳戶檢視範圍:只有「全部」是預設", arguments: [
        (AccountScope.all, true), (.household, false), (.personal, false),
    ])
    func accountScopeDefault(scope: AccountScope, isDefault: Bool) {
        #expect(scope.isDefaultFilter == isDefault)
    }
}
