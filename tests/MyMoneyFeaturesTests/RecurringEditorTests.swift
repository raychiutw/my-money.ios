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

    @Test("新增的預設值：週期支出、每月、1 號、關聯帳戶是「無特定帳戶」(上游 ADR 0011 的選填欄位，#110)")
    func defaults() async {
        let editor = await adding()

        #expect(editor.title == "新增週期收支")
        #expect(editor.type == .expense)
        #expect(editor.cycle == .monthly)
        #expect(editor.dayOfCycle == 1)
        #expect(editor.accountID == nil, "不該自動綁第一個資產帳戶")
    }

    @Test("繳費月份的選項依週期變:月繳沒有、雙月繳 2 個、季繳 3 個、半年繳 6 個、年繳 12 個(文字照上游 web)")
    func monthOptionsFollowTheCycle() async {
        let editor = await adding()
        #expect(editor.monthOptions.isEmpty, "月繳不顯示月份欄位")

        editor.cycle = .bimonthly
        #expect(editor.monthOptions.map(\.value) == [1, 2])
        #expect(editor.monthOptions.map(\.title) == ["單數月（1、3、5、7、9、11月）", "雙數月（2、4、6、8、10、12月）"])

        editor.cycle = .quarterly
        #expect(editor.monthOptions.map(\.title) == ["1、4、7、10 月", "2、5、8、11 月", "3、6、9、12 月"])

        editor.cycle = .semiannual
        #expect(editor.monthOptions.map(\.title) == ["1、7 月", "2、8 月", "3、9 月", "4、10 月", "5、11 月", "6、12 月"])

        editor.cycle = .annual
        #expect(editor.monthOptions.count == 12)
        #expect(editor.monthOptions.first?.title == "每年 1 月" && editor.monthOptions.last?.title == "每年 12 月")
    }

    @Test("切換週期時月份超出新範圍就重設為第一項，範圍內的保留;月繳一律 1")
    func switchingTheCycleResetsAnOutOfRangeMonth() async {
        let editor = await adding()
        editor.cycle = .annual
        editor.monthOfCycle = 11

        editor.cycle = .semiannual
        #expect(editor.monthOfCycle == 1, "11 月不在半年繳的 1–6 範圍內")

        editor.monthOfCycle = 3
        editor.cycle = .quarterly
        #expect(editor.monthOfCycle == 3, "3 在季繳的範圍內，保留")

        editor.cycle = .bimonthly
        #expect(editor.monthOfCycle == 1)

        editor.cycle = .annual
        editor.monthOfCycle = 7
        editor.cycle = .monthly
        #expect(editor.monthOfCycle == 1)
    }

    @Test("新增時送出繳費月份;月繳送 1")
    func savingSendsTheMonth() async {
        let editor = await adding()
        editor.name = "保險費"
        editor.amountText = "3000"
        editor.cycle = .quarterly
        editor.monthOfCycle = 2

        #expect(await editor.save())
        #expect(await repository.createdDrafts.last?.monthOfCycle == 2)

        let monthly = await adding()
        monthly.name = "房租"
        monthly.amountText = "12000"
        #expect(await monthly.save())
        #expect(await repository.createdDrafts.last?.monthOfCycle == 1)
    }

    @Test("編輯既有項目:原本的月份如實還原，儲存後不變")
    func editingRestoresTheMonth() async {
        let quarterly = RecurringItem(
            id: RecurringItemID("sample-insurance-q"), name: "保險費", type: .expense, amount: Money(3000), cycle: .quarterly,
            dayOfCycle: 5, monthOfCycle: 2, accountID: nil, accountName: nil
        )
        let editor = RecurringEditorModel(
            editing: quarterly, repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: dataVersion
        )

        #expect(editor.cycle == .quarterly)
        #expect(editor.monthOfCycle == 2)
        #expect(await editor.save())
        #expect(await repository.updatedDrafts[quarterly.id]?.monthOfCycle == 2)
    }

    @Test("關聯帳戶是選填:可以選特定帳戶，也可以改回「無特定帳戶」，不選也能儲存")
    func accountIsOptional() async {
        let editor = await adding()
        editor.name = "房租"
        editor.amountText = "12000"

        editor.accountID = SampleAccounts.card.id
        editor.accountID = nil

        #expect(await editor.save())
        #expect(await repository.createdDrafts.last?.accountID == nil)
    }

    @Test("資產帳戶載入之前就選了關聯帳戶時，選擇會保留", .timeLimit(.minutes(1)))
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
