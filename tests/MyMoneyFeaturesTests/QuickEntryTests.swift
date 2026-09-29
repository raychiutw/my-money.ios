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

    @Test("預設值：家庭公帳、支出、餐飲、今天、第一個資產帳戶")
    func defaults() async {
        let entry = await model()

        #expect(entry.isShared)
        #expect(entry.type == .expense)
        #expect(entry.category == .dining)
        #expect(entry.date == today)
        #expect(entry.accountID == SampleAccounts.savings.id)
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

    @Test("金額不是正數時提示「請輸入正確的金額」", arguments: ["", "0", "abc", "-5", "1,000", "12.5"])
    func requiresPositiveAmount(amount: String) async {
        let entry = await model()
        entry.amountText = amount

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "請輸入正確的金額")
        #expect(await transactions.createdDrafts.isEmpty)
    }

    @Test("記好一筆後資料版本遞增;只清空金額、備註和日期，其他選擇保留給下一筆")
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
        #expect(entry.accountID == SampleAccounts.card.id)
    }

    @Test("儲存失敗時顯示後端的訊息，資料版本不變")
    func failureShowsMessage() async {
        await transactions.fail(with: .rejected("帳戶不存在"))
        let entry = await model()
        entry.amountText = "120"

        #expect(!(await entry.save()))

        #expect(entry.errorMessage == "帳戶不存在")
        #expect(dataVersion.value == 0)
    }
}
