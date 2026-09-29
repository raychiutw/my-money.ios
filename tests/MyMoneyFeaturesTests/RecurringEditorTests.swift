import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("週期收支的新增與編輯")
struct RecurringEditorTests {
    private let repository = InMemoryRecurringRepository.sample()
    private let dataVersion = DataVersion()

    private func adding() async -> RecurringEditorModel {
        let editor = RecurringEditorModel(
            adding: (), repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: dataVersion
        )
        await editor.prepare()
        return editor
    }

    @Test("新增的預設值：週期支出、每月、1 號、第一個資產帳戶")
    func defaults() async {
        let editor = await adding()

        #expect(editor.title == "新增週期收支")
        #expect(editor.type == .expense)
        #expect(editor.cycle == .monthly)
        #expect(editor.dayOfCycle == 1)
        #expect(editor.accountID == SampleAccounts.savings.id)
    }

    @Test("資產帳戶載入之前就選了關聯帳戶時，不會被第一個資產帳戶蓋掉", .timeLimit(.minutes(1)))
    func prepareKeepsEarlyChoice() async {
        let gate = Gate()
        let editor = RecurringEditorModel(
            adding: (), repository: repository, accounts: InMemoryAccountRepository.sample(gate: gate), dataVersion: dataVersion
        )

        let preparing = Task { await editor.prepare() }
        await gate.waitUntilReached()
        editor.accountID = SampleAccounts.card.id
        await gate.open()
        await preparing.value

        #expect(editor.accountID == SampleAccounts.card.id)
    }

    @Test("名稱必填")
    func nameIsRequired() async {
        let editor = await adding()
        editor.amountText = "500"

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請填寫項目名稱")
    }

    @Test("金額要是正數", arguments: ["", "0", "abc", "1,000", "12.5"])
    func amountMustBePositive(amount: String) async {
        let editor = await adding()
        editor.name = "網路費"
        editor.amountText = amount

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入有效金額")
    }

    @Test("新增成功後資料版本遞增;可以不指定關聯帳戶")
    func createWithoutAccount() async {
        let editor = await adding()
        editor.name = "  網路費  "
        editor.amountText = "899"
        editor.cycle = .quarterly
        editor.dayOfCycle = 12
        editor.accountID = nil

        #expect(await editor.save())

        #expect(await repository.createdDrafts == [RecurringDraft(
            name: "網路費", type: .expense, amount: Money(899), cycle: .quarterly, dayOfCycle: 12, accountID: nil
        )])
        #expect(dataVersion.value == 1)
    }

    @Test("編輯時帶入原值，儲存時 PUT 原本的項目")
    func editing() async {
        let salary = InMemoryRecurringRepository.sampleItems[2]
        let editor = RecurringEditorModel(
            editing: salary, repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: dataVersion
        )
        await editor.prepare()

        #expect(editor.title == "編輯週期收支")
        #expect(editor.name == "薪水")
        #expect(editor.type == .income)
        #expect(editor.amountText == "45000")
        #expect(editor.dayOfCycle == 25)

        editor.amountText = "46000"
        #expect(await editor.save())

        #expect(await repository.updatedDrafts[salary.id]?.amount == Money(46000))
        #expect(dataVersion.value == 1)
    }
}
