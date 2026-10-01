import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("記一筆")
struct QuickEntryTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let transactions = InMemoryTransactionRepository(transactions: [])
    private let dataVersion = DataVersion()

    private func model(accounts: [Account] = SampleAccounts.all) async -> QuickEntryModel {
        let model = QuickEntryModel(
            transactions: transactions,
            accounts: InMemoryAccountRepository(accounts: accounts, summary: .zero),
            dataVersion: dataVersion,
            today: { today }
        )
        await model.prepare()
        return model
    }

    @Test("預設值：家庭公帳、支出、餐飲、今天;帳戶是空的，不預選任何一個(上游 ADR 0011，#109)")
    func defaults() async {
        let entry = await model()

        #expect(entry.isShared)
        #expect(entry.type == .expense)
        #expect(entry.category == .dining)
        #expect(entry.date == today)
        #expect(entry.accountID == nil, "不該預選第一個帳戶")
        #expect(entry.amountText == "")
    }

    @Test("切到收入時分類變成「薪資」,切回支出變成「餐飲」")
    func switchingTypeResetsCategory() async {
        let entry = await model()
        entry.category = TransactionCategory("交通")

        entry.type = .income
        #expect(entry.category == .salary)
        #expect(entry.categories == TransactionCategory.incomeCategories)

        entry.type = .expense
        #expect(entry.category == .dining)
        #expect(entry.categories == TransactionCategory.expenseCategories)
    }

    @Test("還沒有任何資產帳戶時提示先建立")
    func requiresAnAccount() async {
        let entry = await model(accounts: [])
        entry.amountText = "120"

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "請先至「帳戶」建立至少一個帳戶")
    }

    @Test("有資產帳戶但沒選帳戶就儲存:提示「請選擇扣款或存入帳戶」，不送出")
    func requiresAnAccountChoice() async {
        let entry = await model()
        entry.amountText = "120"

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "請選擇扣款或存入帳戶")
        #expect(await transactions.createdDrafts.isEmpty)
        #expect(dataVersion.value == 0)
    }

    @Test("每次打開一筆新的記一筆，帳戶都清成空的，連續記帳也一樣(上游 ADR 0011，#109)")
    func startingANewEntryClearsTheAccount() async {
        let entry = await model()
        entry.accountID = SampleAccounts.card.id

        entry.startNewEntry()

        #expect(entry.accountID == nil)
    }

    /// 表單的 `.task` 在從帳戶清單頁返回時會再跑一次 `prepare`:不能因此把剛選的帳戶清掉，也不能重設分類的鎖定。
    @Test("從帳戶清單頁返回(prepare 再跑一次)時，保留剛選的帳戶與手動選過分類的鎖定")
    func prepareAgainKeepsTheChoices() async {
        let entry = await model()
        entry.chooseCategory(TransactionCategory("娛樂"))
        entry.accountID = SampleAccounts.card.id

        await entry.prepare()

        #expect(entry.accountID == SampleAccounts.card.id, "返回表單之後帳戶被清掉了")
        entry.note = "Netflix 月費"
        #expect(entry.category == TransactionCategory("娛樂"), "返回表單之後分類的鎖定被重設了")
    }

    @Test("金額不是正數時提示「請輸入正確的金額」", arguments: ["", "0", "abc", "-5", "1,000", "12.5"])
    func requiresPositiveAmount(amount: String) async {
        let entry = await model()
        entry.accountID = SampleAccounts.savings.id
        entry.amountText = amount

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "請輸入正確的金額")
        #expect(await transactions.createdDrafts.isEmpty)
    }

    @Test("記好一筆後資料版本遞增;清空金額、備註、日期和帳戶，類型、分類、歸屬保留給下一筆")
    func savingKeepsSelectionsForNextEntry() async {
        let entry = await model()
        entry.isShared = false
        entry.category = TransactionCategory("交通")
        entry.accountID = SampleAccounts.card.id
        entry.amountText = "250"
        entry.note = "  計程車  "
        entry.date = CalendarDay(year: 2026, month: 9, day: 26)

        #expect(await entry.save())

        #expect(await transactions.createdDrafts == [TransactionDraft(
            accountID: SampleAccounts.card.id,
            type: .expense,
            category: TransactionCategory("交通"),
            amount: Money(250),
            note: "計程車",
            date: CalendarDay(year: 2026, month: 9, day: 26),
            isShared: false
        )])
        #expect(dataVersion.value == 1)
        #expect(entry.amountText == "")
        #expect(entry.note == "")
        #expect(entry.date == today)
        #expect(!entry.isShared)
        #expect(entry.category == TransactionCategory("交通"))
        #expect(entry.accountID == nil, "帳戶不沿用上一筆")
    }

    @Test("儲存失敗時顯示後端的訊息，資料版本不變")
    func failureShowsMessage() async {
        await transactions.fail(with: .rejected("帳戶不存在"))
        let entry = await model()
        entry.accountID = SampleAccounts.savings.id
        entry.amountText = "120"

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "帳戶不存在")
        #expect(dataVersion.value == 0)
    }
}
