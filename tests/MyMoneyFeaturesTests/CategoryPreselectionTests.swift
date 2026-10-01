import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("記一筆依備註預選分類:詞庫、歷史、手動鎖定與提示(上游 ADR-0009,#99、#102)")
struct CategoryPreselectionTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let dataVersion = DataVersion()

    private func transaction(_ note: String, _ category: String, daysAgo: Int = 1, type: TransactionType = .expense) -> Transaction {
        Transaction(
            id: TransactionID("h-\(note)-\(daysAgo)"), accountID: SampleAccounts.savings.id, accountName: nil, type: type,
            category: TransactionCategory(category), amount: Money(100), note: note,
            date: CalendarDay(year: today.year, month: today.month, day: today.day - daysAgo), isShared: true, recorderName: nil
        )
    }

    private func entry(history: [Transaction] = [], loadHistory: Bool = true) async -> (QuickEntryModel, InMemoryTransactionRepository) {
        let repository = InMemoryTransactionRepository(transactions: history)
        let model = QuickEntryModel(
            transactions: repository,
            accounts: InMemoryAccountRepository(accounts: SampleAccounts.all, summary: .zero),
            dataVersion: dataVersion,
            today: { today }
        )
        await model.prepare()
        if loadHistory { await model.loadNoteHistory() }
        return (model, repository)
    }

    // MARK: - 詞庫層

    @Test("輸入備註，分類自動預選，並顯示「智慧推薦為【分類】」")
    func lexiconPreselectsCategory() async {
        let (entry, _) = await entry()

        entry.note = "中油加油"

        #expect(entry.category == TransactionCategory("汽機車輛"))
        #expect(entry.categoryHintText == "智慧推薦為【汽機車輛】")
    }

    @Test("收入也有推薦，而且用收入的分類清單")
    func lexiconForIncome() async {
        let (entry, _) = await entry()
        entry.type = .income

        entry.note = "育兒津貼"

        #expect(entry.category == TransactionCategory("政府補貼"))
        #expect(entry.categoryHintText == "智慧推薦為【政府補貼】")
    }

    @Test("備註沒命中任何規則時，分類維持目前的選擇，提示清掉")
    func noMatchKeepsTheCategory() async {
        let (entry, _) = await entry()
        entry.note = "中油加油"
        #expect(entry.categoryHintText != nil)

        entry.note = "zzz"

        #expect(entry.category == TransactionCategory("汽機車輛"), "沒命中時不該動分類")
        #expect(entry.categoryHintText == nil)
    }

    @Test("手動選過分類就鎖定:之後再打字也不覆蓋，提示清掉")
    func manualChoiceLocksTheCategory() async {
        let (entry, _) = await entry()
        entry.note = "中油加油"

        entry.chooseCategory(TransactionCategory("娛樂"))
        #expect(entry.category == TransactionCategory("娛樂"))
        #expect(entry.categoryHintText == nil)

        entry.note = "Netflix 月費"

        #expect(entry.category == TransactionCategory("娛樂"), "鎖定之後不該被推薦覆蓋")
        #expect(entry.categoryHintText == nil)
    }

    @Test("每次重新打開記一筆都從沒鎖定、沒有提示開始")
    func reopeningResetsTheLockAndHint() async {
        let (entry, _) = await entry()
        entry.chooseCategory(TransactionCategory("娛樂"))
        entry.note = ""
        entry.note = "先寫著"

        await entry.prepare()
        entry.note = "Netflix"

        #expect(entry.category == TransactionCategory("數位訂閱"))
        #expect(entry.categoryHintText == "智慧推薦為【數位訂閱】")
    }

    @Test("切換支出與收入:分類重設成該類型的預設值，提示清掉")
    func switchingTypeClearsTheHint() async {
        let (entry, _) = await entry()
        entry.note = "中油加油"

        entry.type = .income

        #expect(entry.category == .salary)
        #expect(entry.categoryHintText == nil)
    }

    @Test("儲存成功後備註清空，分類保留給下一筆，提示清掉")
    func savingClearsTheHint() async {
        let (entry, _) = await entry()
        entry.amountText = "120"
        entry.note = "中油加油"

        #expect(await entry.save())

        #expect(entry.note == "")
        #expect(entry.category == TransactionCategory("汽機車輛"))
        #expect(entry.categoryHintText == nil)
    }

    // MARK: - 歷史層

    @Test("歷史優先於詞庫:記過的備註採用當時選的分類，提示是「依歷史習慣推薦」")
    func historyBeatsLexicon() async {
        let (entry, _) = await entry(history: [transaction("全聯", "餐飲")])

        entry.note = "全聯"

        #expect(entry.category == .dining, "詞庫會推薦生活，但歷史優先")
        #expect(entry.categoryHintText == "依歷史習慣推薦【餐飲】")
    }

    @Test("只取近 3 個月的歷史，並排除系統分類")
    func historyIsLimitedToThreeMonthsAndSkipsSystemCategories() async {
        let (entry, repository) = await entry(history: [
            transaction("全聯", "餐飲"),
            transaction("中油", "信用卡還款"),
        ])

        let query = await repository.queries.first
        #expect(query?.from == today.addingMonths(-3), "歷史要從 3 個月前開始查")
        #expect(query?.to == today)

        entry.note = "中油"
        #expect(entry.categoryHintText == "智慧推薦為【汽機車輛】", "系統分類不進歷史，改走詞庫")
    }

    @Test("歷史載入失敗時記一筆照常可用:少了歷史推薦，仍有詞庫推薦")
    func historyFailureFallsBackToLexicon() async {
        let repository = InMemoryTransactionRepository(transactions: [transaction("全聯", "餐飲")])
        await repository.fail(with: .rejected("連不上伺服器"))
        let model = QuickEntryModel(
            transactions: repository,
            accounts: InMemoryAccountRepository(accounts: SampleAccounts.all, summary: .zero),
            dataVersion: dataVersion,
            today: { today }
        )
        await model.prepare()
        await model.loadNoteHistory()

        model.note = "全聯"

        #expect(model.category == TransactionCategory("生活"), "沒有歷史，改用詞庫")
        #expect(model.categoryHintText == "智慧推薦為【生活】")
        #expect(model.errorMessage == nil, "歷史載入失敗不該擋住記帳或顯示錯誤")
    }

    // MARK: - 編輯既有交易

    @Test("編輯既有交易時分類一開始就是鎖定的:改備註不會換掉分類")
    func editorNeverPreselects() async {
        let original = transaction("耳機", "購物")
        let editor = TransactionEditorModel(
            editing: original,
            transactions: InMemoryTransactionRepository(transactions: []),
            accounts: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion
        )
        await editor.prepare()

        editor.note = "中油加油"

        #expect(editor.category == TransactionCategory("購物"))
        #expect(editor.categoryHintText == nil)

        editor.chooseCategory(TransactionCategory("娛樂"))
        #expect(editor.category == TransactionCategory("娛樂"))
    }
}
