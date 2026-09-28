import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("交易頁的篩選、刪除與匯出")
struct TransactionFilterTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func loadedList(
        repository: InMemoryTransactionRepository? = nil,
        dataVersion: DataVersion = DataVersion()
    ) async -> (TransactionsModel, InMemoryTransactionRepository) {
        let repository = repository ?? InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today))
        let list = TransactionsModel(repository: repository, dataVersion: dataVersion, today: { today })
        await list.load()
        return (list, repository)
    }

    @Test("只看收入時，列表與加總都只算收入")
    func filtersByType() async {
        let (list, _) = await loadedList()

        list.typeFilter = .income

        #expect(list.count == 1)
        #expect(list.totalIncome == Money(45000))
        #expect(list.totalExpense == Money(0))
        #expect(list.days.flatMap(\.transactions).allSatisfy { $0.type == .income })
    }

    @Test("分類選項隨類型改變，「其他」不會重複")
    func categoryOptionsFollowType() async {
        let (list, _) = await loadedList()

        #expect(list.categoryOptions.filter { $0.name == "其他" }.count == 1)

        list.typeFilter = .expense
        #expect(list.categoryOptions == TransactionCategory.expenseCategories)

        list.typeFilter = .income
        #expect(list.categoryOptions == TransactionCategory.incomeCategories)
    }

    @Test("切換類型後，不屬於新類型的分類篩選會清掉")
    func switchingTypeClearsIncompatibleCategory() async {
        let (list, _) = await loadedList()
        list.typeFilter = .expense
        list.categoryFilter = .dining

        list.typeFilter = .income

        #expect(list.categoryFilter == nil)
    }

    @Test("依分類篩選")
    func filtersByCategory() async {
        let (list, _) = await loadedList()

        list.categoryFilter = .dining

        #expect(list.days.flatMap(\.transactions).map(\.note) == ["午餐"])
    }

    @Test("關鍵字不分大小寫，比對備註、分類、帳戶名稱與記帳人", arguments: [
        ("耳機", ["耳機"]),
        ("購物", ["耳機"]),
        ("ios 測試信用卡", ["耳機", "繳納【iOS 測試信用卡】卡費"]),
        ("小明", ["耳機", "午餐", "繳納【iOS 測試信用卡】卡費", ""]),
        ("沒有這個字", []),
    ])
    func filtersByKeyword(keyword: String, notes: [String]) async {
        let (list, _) = await loadedList()

        list.keyword = keyword

        #expect(list.days.flatMap(\.transactions).map(\.note) == notes)
    }

    @Test("刪除交易紀錄後資料版本遞增")
    func deletingBumpsDataVersion() async {
        let dataVersion = DataVersion()
        let (list, repository) = await loadedList(dataVersion: dataVersion)
        let lunch = list.days.flatMap(\.transactions).first { $0.note == "午餐" }!

        await list.delete(lunch)

        #expect(await repository.deletedIDs == [lunch.id])
        #expect(dataVersion.value == 1)
    }

    @Test("「信用卡還款」不能編輯也不能刪除")
    func repaymentIsLocked() async {
        let dataVersion = DataVersion()
        let (list, repository) = await loadedList(dataVersion: dataVersion)
        let repayment = list.days.flatMap(\.transactions).first { $0.isCreditCardRepayment }!

        #expect(!list.canModify(repayment))
        #expect(list.makeEditor(for: repayment) == nil)
        await list.delete(repayment)

        #expect(await repository.deletedIDs.isEmpty)
        #expect(dataVersion.value == 0)
    }

    @Test("刪除前的確認文字")
    func deleteConfirmation() async {
        let (list, _) = await loadedList()

        #expect(list.deleteConfirmation == "確定要刪除這筆交易紀錄嗎？")
    }

    @Test("刪除失敗時顯示後端的訊息")
    func deleteFailureShowsAlert() async {
        let (list, repository) = await loadedList()
        let lunch = list.days.flatMap(\.transactions).first { $0.note == "午餐" }!
        await repository.fail(with: .rejected("紀錄不存在"))

        await list.delete(lunch)

        #expect(list.alertMessage == "紀錄不存在")
    }

    @Test("匯出目前起迄日的 CSV,檔名跟 web 一樣")
    func exportsCurrentPeriod() async throws {
        let (list, repository) = await loadedList()

        let export = list.csvExport()
        let data = try await export.fetch()

        #expect(export.fileName == "my-money-2026-09-28.csv")
        #expect(data == InMemoryTransactionRepository.sampleCSV)
        #expect(await repository.exportQueries.last == .init(from: CalendarDay(year: 2026, month: 9, day: 1), to: today))
    }
}
