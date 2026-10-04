import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("編輯收支明細")
struct TransactionEditorTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let repository = InMemoryTransactionRepository(transactions: [])
    private let dataVersion = DataVersion()

    private func editor(for transaction: Transaction) async -> TransactionEditorModel {
        let editor = TransactionEditorModel(
            editing: transaction,
            transactions: repository,
            accounts: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion
        )
        await editor.prepare()
        return editor
    }

    private var headphones: Transaction {
        SampleTransactions.make(today: today).first { $0.note == "耳機" }!
    }

    @Test("帶入原值，家人記的也能編輯")
    func prefillsOriginalValues() async {
        let editor = await editor(for: headphones)

        #expect(editor.title == "編輯收支明細")
        #expect(!editor.isShared)
        #expect(editor.type == .expense)
        #expect(editor.category == TransactionCategory("購物"))
        #expect(editor.amountText == "880")
        #expect(editor.note == "耳機")
        #expect(editor.date == today)
        #expect(editor.accountID == SampleAccounts.card.id)
    }

    @Test("儲存時 PUT 原本的紀錄，資料版本遞增")
    func savingUpdatesTransaction() async {
        let editor = await editor(for: headphones)
        editor.amountText = "990"
        editor.isShared = true

        #expect(await editor.save())

        #expect(await repository.updatedDrafts == [headphones.id: TransactionDraft(
            accountID: SampleAccounts.card.id,
            type: .expense,
            category: TransactionCategory("購物"),
            amount: Money(990),
            note: "耳機",
            date: today,
            isShared: true
        )])
        #expect(dataVersion.value == 1)
    }

    @Test("金額無效時提示「請輸入有效金額」")
    func requiresValidAmount() async {
        let editor = await editor(for: headphones)
        editor.amountText = "0"

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入有效金額")
        #expect(dataVersion.value == 0)
    }

    @Test("沒選資產帳戶時提示「請先建立並選擇帳戶」")
    func requiresAccount() async {
        let editor = await editor(for: headphones)
        editor.accountID = nil

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請先建立並選擇帳戶")
    }

    // MARK: 信用卡「列入下期帳單」(上游 ADR 0020，#184)

    @Test("只有選了信用卡才有「列入下期帳單」;切到別的帳戶就收起並重設")
    func deferOnlyForCreditCards() async {
        let editor = await editor(for: headphones)
        #expect(editor.isCreditCardSelected, "耳機是刷卡的")

        editor.defersToNextStatement = true
        editor.accountID = SampleAccounts.savings.id

        #expect(!editor.isCreditCardSelected)
        #expect(!editor.defersToNextStatement, "切到活存帳戶之後，延期勾選要重設")
    }

    @Test("編輯一筆已延至下期的刷卡:勾選帶入原值;取消勾選後儲存送出 false")
    func prefillAndSendDeferFlag() async {
        let deferred = Transaction(
            id: TransactionID("deferred"), accountID: SampleAccounts.card.id, accountName: SampleAccounts.card.name,
            type: .expense, category: .dining, amount: Money(321), note: "延至下期", date: today, isShared: false,
            recorderName: nil, billing: .deferred
        )
        let editor = await editor(for: deferred)
        #expect(editor.defersToNextStatement)

        editor.defersToNextStatement = false
        #expect(await editor.save())

        #expect(await repository.updatedDrafts[deferred.id]?.defersToNextStatement == false)
    }

    @Test("非信用卡帳戶就算勾選狀態殘留，也不送延期")
    func nonCardNeverSendsDefer() async {
        let editor = await editor(for: headphones)
        editor.defersToNextStatement = true
        editor.accountID = SampleAccounts.savings.id
        editor.defersToNextStatement = true

        #expect(await editor.save())

        #expect(await repository.updatedDrafts[headphones.id]?.defersToNextStatement == false)
    }
}
