import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 記一筆的「帶入週期項目」(上游 2631757,上游 CONTEXT「Recurring Preset Selection」,#361)。
@MainActor
@Suite("記一筆帶入週期項目")
struct RecurringPresetTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let transactions = InMemoryTransactionRepository(transactions: [])

    private func model(recurring: InMemoryRecurringRepository = .sample(includesFamilyEntries: true)) async -> QuickEntryModel {
        let model = QuickEntryModel(
            transactions: transactions,
            accounts: InMemoryAccountRepository(accounts: SampleAccounts.all, summary: .zero),
            recurring: recurring,
            dataVersion: DataVersion(),
            today: { today }
        )
        model.startNewEntry()
        await model.prepare()
        await model.loadRecurringPresets()
        return model
    }

    @Test("候選依類型篩選，包含私帳與家人的公帳;選項是「[公帳]／[私帳] 名稱 (金額)」")
    func candidatesFilteredByType() async {
        let entry = await model()

        #expect(entry.presetCandidates.map(\.name) == ["房租", "年繳保費", "網路費"])
        #expect(entry.presetCandidates.map(\.presetLabel) == [
            "[公帳] 房租 ($12,000)", "[私帳] 年繳保費 ($24,000)", "[公帳] 網路費 ($899)",
        ])
        #expect(entry.presetTitle == "帶入週期支出項目(選填)")

        entry.type = .income
        #expect(entry.presetCandidates.map(\.name) == ["薪水"])
        #expect(entry.presetTitle == "帶入週期收入項目(選填)")
    }

    @Test("選了週期項目只帶入金額與備註，分類照備註推薦;不預選帳戶、歸屬，日期不動")
    func selectingFillsAmountAndNote() async {
        let entry = await model()
        entry.isShared = false

        entry.selectedPresetID = RecurringItemID("sample-rent")

        #expect(entry.amountText == "12000")
        #expect(entry.note == "房租")
        #expect(entry.category == TransactionCategory("居家水電"))
        #expect(entry.categoryHintText == "智慧推薦為【居家水電】")
        #expect(entry.accountID == nil, "項目有關聯帳戶也不預選(顯式帳戶原則)")
        #expect(entry.isShared == false, "公帳項目也不改歸屬")
        #expect(entry.date == today)
    }

    @Test("手動選過分類，帶入週期項目不覆蓋分類")
    func manualCategoryNotOverridden() async {
        let entry = await model()
        entry.chooseCategory(TransactionCategory("交通"))

        entry.selectedPresetID = RecurringItemID("sample-rent")

        #expect(entry.note == "房租")
        #expect(entry.category == TransactionCategory("交通"))
        #expect(entry.categoryHintText == nil)
    }

    @Test("備註原本就等於項目名稱時，選了週期項目仍重新推薦分類(web 每次選取都重算)")
    func selectingWithSameNoteStillRecommends() async {
        let entry = await model()
        entry.note = "房租"
        // 切到收入再切回支出:分類重設為餐飲、推薦清掉，備註仍是「房租」。
        entry.type = .income
        entry.type = .expense
        #expect(entry.category == .dining)

        entry.selectedPresetID = RecurringItemID("sample-rent")

        #expect(entry.category == TransactionCategory("居家水電"))
        #expect(entry.categoryHintText == "智慧推薦為【居家水電】")
    }

    @Test("有週期項目但沒有目前類型的，不顯示選單")
    func noCandidatesOfCurrentType() async throws {
        let expenses = try await InMemoryRecurringRepository.sample().items(scope: .all).filter { $0.type == .expense }
        let entry = await model(recurring: InMemoryRecurringRepository(items: expenses))
        #expect(!entry.presetCandidates.isEmpty)

        entry.type = .income

        #expect(entry.presetCandidates.isEmpty)
    }

    @Test("編輯收支明細不顯示選單")
    func editorHasNoCandidates() async {
        let editor = TransactionEditorModel(
            editing: Transaction(
                id: TransactionID("rent"), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name,
                type: .expense, category: TransactionCategory("居家水電"), amount: Money(12000), note: "房租", date: today,
                isShared: true, recorderName: "小明", recordedAt: nil
            ),
            transactions: transactions, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion()
        )
        await editor.prepare()
        await editor.loadRecurringPresets()

        #expect(editor.presetCandidates.isEmpty)
    }

    @Test("選回「不套用」保留已填的金額與備註;之後仍可自由修改")
    func clearingKeepsFilledFields() async {
        let entry = await model()
        entry.selectedPresetID = RecurringItemID("sample-rent")
        entry.amountText = "11500"

        entry.selectedPresetID = nil

        #expect(entry.amountText == "11500")
        #expect(entry.note == "房租")
    }

    @Test("切換支出／收入時選單重設為「不套用」")
    func switchingTypeResetsSelection() async {
        let entry = await model()
        entry.selectedPresetID = RecurringItemID("sample-rent")

        entry.type = .income

        #expect(entry.selectedPresetID == nil)
    }

    @Test("送出成功與重新打開都重設為「不套用」;送出的收支只是一般收支")
    func resetsAfterSaveAndReopen() async throws {
        let entry = await model()
        entry.selectedPresetID = RecurringItemID("sample-rent")
        entry.accountID = SampleAccounts.savings.id
        #expect(await entry.save())
        #expect(entry.selectedPresetID == nil)
        let draft = try #require(await transactions.createdDrafts.last)
        #expect(draft.amount == Money(12000))
        #expect(draft.note == "房租")

        entry.selectedPresetID = RecurringItemID("sample-insurance")
        entry.startNewEntry()
        #expect(entry.selectedPresetID == nil)
    }

    @Test("週期項目載入失敗時沒有候選，記一筆照常可用")
    func loadFailureLeavesNoCandidates() async {
        let recurring = InMemoryRecurringRepository.sample()
        await recurring.fail(with: .unreadableResponse)
        let entry = await model(recurring: recurring)

        #expect(entry.presetCandidates.isEmpty)
        entry.accountID = SampleAccounts.savings.id
        entry.amountText = "80"
        #expect(await entry.save())
    }
}
