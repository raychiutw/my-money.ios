import Foundation
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

    /// 篩選 sheet 改的是一份草稿(#74):一項一項改的時候不查詢，按「完成」才一次套用，只發一次查詢。
    @Test("篩選草稿按「完成」才套用，而且只查詢一次")
    func draftAppliesOnDoneWithOneQuery() async {
        let (list, repository) = await loadedList()
        let queriesBeforeEditing = await repository.queries.count

        list.editFilter()
        list.filterDraft.scope = .household
        list.filterDraft.to = CalendarDay(year: 2026, month: 9, day: 30)
        list.filterDraft.type = .expense
        list.filterDraft.category = .dining

        #expect(list.isEditingFilter)
        #expect(list.filter.scope == .all, "還沒按完成，視角就變了")
        #expect(list.filter.to == today, "還沒按完成，迄日就變了")
        #expect(list.count == 4, "還沒按完成，清單就被篩選了")
        #expect(await repository.queries.count == queriesBeforeEditing, "還沒按完成就查詢了")

        await list.applyFilter()

        #expect(!list.isEditingFilter)
        let queries = await repository.queries.dropFirst(queriesBeforeEditing)
        #expect(queries.count == 1, "按完成後查詢了 \(queries.count) 次")
        #expect(queries.first?.scope == .household)
        #expect(queries.first?.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(queries.first?.to == CalendarDay(year: 2026, month: 9, day: 30))
        #expect(list.days.flatMap(\.transactions).map(\.note) == ["午餐"])
    }

    /// 篩選改成 sheet 之後，套用篩選的查詢跟第一次載入是各自的 Task,不會取消舊的(code review)。
    @Test("舊的查詢比套用篩選的查詢晚回來時，清單維持新篩選的結果", .timeLimit(.minutes(1)))
    func staleQueryDoesNotOverwriteAppliedFilter() async {
        let repository = InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today))
        let gate = Gate()
        await repository.holdNextQuery(at: gate)
        let list = TransactionsModel(repository: repository, dataVersion: DataVersion(), today: { today })
        let firstLoad = Task { await list.load() }
        await gate.waitUntilReached()

        list.editFilter()
        list.filterDraft.from = today
        await list.applyFilter()
        let applied = list.days.flatMap(\.transactions).map(\.id)

        await gate.open()
        await firstLoad.value

        #expect(list.filter.from == today)
        #expect(list.days.flatMap(\.transactions).map(\.id) == applied, "本月的舊查詢蓋掉了只查今天的結果")
    }

    @Test("只改類型或分類時，按「完成」不重新查詢(只在本機過濾)")
    func applyingLocalFilterDoesNotQuery() async {
        let (list, repository) = await loadedList()
        let queriesBeforeEditing = await repository.queries.count

        list.editFilter()
        list.filterDraft.type = .expense
        list.filterDraft.category = .dining
        await list.applyFilter()

        #expect(await repository.queries.count == queriesBeforeEditing, "只改類型和分類也重新查詢了")
        #expect(list.days.flatMap(\.transactions).map(\.note) == ["午餐"])
    }

    @Test("「重設為本月」把草稿的起迄日改回本月 1 號到今天，其他篩選不變")
    func resetDraftToThisMonth() async {
        let (list, _) = await loadedList()
        list.editFilter()
        list.filterDraft.from = CalendarDay(year: 2026, month: 7, day: 1)
        list.filterDraft.to = CalendarDay(year: 2026, month: 8, day: 31)
        list.filterDraft.scope = .household
        list.filterDraft.type = .expense

        list.resetFilterDraftToThisMonth()

        #expect(list.filterDraft.from == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(list.filterDraft.to == today)
        #expect(list.filterDraft.scope == .household)
        #expect(list.filterDraft.type == .expense)
        #expect(list.filter.from == CalendarDay(year: 2026, month: 9, day: 1), "重設改的是草稿，不是套用中的篩選")
    }

    /// 迄日的 DatePicker 選不到起日之前;起日改到迄日之後時，迄日跟著改。
    @Test("迄日不早於起日：起日改到迄日之後時，迄日跟著改成起日")
    func toFollowsFrom() async {
        let (list, _) = await loadedList()
        list.editFilter()

        list.filterDraft.from = CalendarDay(year: 2026, month: 10, day: 5)

        #expect(list.filterDraft.to == CalendarDay(year: 2026, month: 10, day: 5))

        list.filterDraft.from = CalendarDay(year: 2026, month: 9, day: 3)

        #expect(list.filterDraft.to == CalendarDay(year: 2026, month: 10, day: 5), "起日往前改時，迄日不用動")
    }

    @Test("按「取消」時篩選不變，也不查詢;再打開時草稿是目前套用的篩選")
    func cancellingKeepsFilter() async {
        let (list, repository) = await loadedList()
        let applied = list.filter
        let queriesBeforeEditing = await repository.queries.count

        list.editFilter()
        list.filterDraft.scope = .personal
        list.filterDraft.type = .income
        list.cancelFilter()

        #expect(!list.isEditingFilter, "按取消後篩選 sheet 沒有關閉")
        #expect(list.filter == applied)
        #expect(list.count == 4)
        #expect(await repository.queries.count == queriesBeforeEditing, "按取消後查詢了")

        list.editFilter()
        #expect(list.filterDraft == applied, "再打開時還留著取消掉的草稿")
    }

    /// 目前篩選的一句話描述，當篩選按鈕的 VoiceOver 值(畫面上不再顯示副標題，#108)。日期用系統格式(DESIGN.md「日期」)。
    @Test("篩選按鈕的 VoiceOver 值描述目前的範圍：視角、起迄日，有篩選時加上類型與分類")
    func filterSummaryDescribesCurrentFilter() async {
        let list = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            dataVersion: DataVersion(), locale: Locale(identifier: "zh_Hant_TW"), today: { today }
        )
        await list.load()

        #expect(list.filterSummary == "全部・9月1日–9月28日")

        list.editFilter()
        list.filterDraft.scope = .household
        list.filterDraft.to = CalendarDay(year: 2026, month: 9, day: 30)
        list.filterDraft.type = .expense
        list.filterDraft.category = .dining
        #expect(list.filterSummary == "全部・9月1日–9月28日", "還沒按完成，描述就變了")
        await list.applyFilter()

        #expect(list.filterSummary == "家庭公帳・9月1日–9月30日・支出・餐飲")
    }

    @Test("只看收入時，列表與加總都只算收入")
    func filtersByType() async {
        let (list, _) = await loadedList()

        list.editFilter()
        list.filterDraft.type = .income
        await list.applyFilter()

        #expect(list.count == 1)
        #expect(list.totalIncome == Money(45000))
        #expect(list.totalExpense == Money(0))
        #expect(list.days.flatMap(\.transactions).allSatisfy { $0.type == .income })
    }

    @Test("分類選項隨類型改變，「其他」不會重複")
    func categoryOptionsFollowType() async {
        let (list, _) = await loadedList()
        list.editFilter()

        #expect(list.filterDraft.categoryOptions.filter { $0.name == "其他" }.count == 1)

        list.filterDraft.type = .expense
        #expect(list.filterDraft.categoryOptions == TransactionCategory.expenseCategories)

        list.filterDraft.type = .income
        #expect(list.filterDraft.categoryOptions == TransactionCategory.incomeCategories)
    }

    @Test("切換類型後，不屬於新類型的分類篩選會清掉")
    func switchingTypeClearsIncompatibleCategory() async {
        let (list, _) = await loadedList()
        list.editFilter()
        list.filterDraft.type = .expense
        list.filterDraft.category = .dining

        list.filterDraft.type = .income

        #expect(list.filterDraft.category == nil)
    }

    @Test("依分類篩選")
    func filtersByCategory() async {
        let (list, _) = await loadedList()

        list.editFilter()
        list.filterDraft.category = .dining
        await list.applyFilter()

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

    @Test("刪除收支明細後資料版本遞增")
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
        let repayment = list.days.flatMap(\.transactions).first { $0.category == .creditCardRepayment }!

        #expect(!list.canModify(repayment))
        #expect(list.makeEditor(for: repayment) == nil)
        await list.delete(repayment)

        #expect(await repository.deletedIDs.isEmpty)
        #expect(dataVersion.value == 0)
    }

    @Test("刪除前的確認文字")
    func deleteConfirmation() async {
        let (list, _) = await loadedList()

        #expect(list.deleteConfirmation == "確定要刪除這筆收支明細嗎？")
    }

    @Test("刪除失敗時顯示後端的訊息")
    func deleteFailureShowsAlert() async {
        let (list, repository) = await loadedList()
        let lunch = list.days.flatMap(\.transactions).first { $0.note == "午餐" }!
        await repository.fail(with: .rejected("交易記錄不存在"))

        await list.delete(lunch)

        #expect(list.alertMessage == "交易記錄不存在")
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
