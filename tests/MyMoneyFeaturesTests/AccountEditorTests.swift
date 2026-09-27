import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("資金帳戶的新增與編輯")
struct AccountEditorTests {
    private let repository = InMemoryAccountRepository(accounts: [], summary: .zero)
    private let dataVersion = DataVersion()

    private func adding(_ kind: AccountKind) -> AccountEditorModel {
        AccountEditorModel(adding: kind, repository: repository, dataVersion: dataVersion, randomColor: { "#95E1D3" })
    }

    @Test("新增銀行存款帳戶的預設值：餘額空白(存成 0)、沒有信用卡欄位、隨機代表色")
    func bankDefaults() {
        let editor = adding(.bank)

        #expect(editor.title == "新增銀行存款帳戶")
        #expect(editor.amountLabel == "餘額")
        #expect(editor.amountText == "")
        #expect(editor.creditLimitText == "")
        #expect(editor.statementDay == nil)
        #expect(editor.paymentDueDay == nil)
        #expect(editor.colorHex == "#95E1D3")
        #expect(editor.canChangeKind)
    }

    @Test("新增信用卡的預設值：已出帳與未出帳空白(存成 0)、額度 100000、結帳日 15、繳款日 5")
    func creditCardDefaults() {
        let editor = adding(.creditCard)

        #expect(editor.title == "新增信用卡")
        #expect(editor.amountLabel == "已出帳待繳金額")
        #expect(editor.amountText == "")
        #expect(editor.unbilledText == "")
        #expect(editor.creditLimitText == "100000")
        #expect(editor.statementDay == 15)
        #expect(editor.paymentDueDay == 5)
    }

    @Test("新增時從信用卡切到銀行存款帳戶，不會把信用卡的額度與日期存進去")
    func switchingToBankDropsCardFields() async {
        let editor = adding(.creditCard)
        editor.name = "薪轉戶"

        editor.kind = .bank
        #expect(await editor.save())

        #expect(await repository.createdDrafts == [.bank(BankAccountDraft(
            name: "薪轉戶", colorHex: "#95E1D3", balance: Money(0), isJointFund: false
        ))])
    }

    @Test("新增時從銀行存款帳戶切到信用卡，套用信用卡的預設值")
    func switchingToCardAppliesCardDefaults() {
        let editor = adding(.bank)

        editor.kind = .creditCard

        #expect(editor.creditLimitText == "100000")
        #expect(editor.statementDay == 15)
        #expect(editor.paymentDueDay == 5)
        #expect(editor.title == "新增信用卡")
    }

    @Test("編輯時帶入原值，而且不能改類型")
    func editingPrefillsAndLocksKind() {
        let editor = AccountEditorModel(editing: .creditCard(SampleAccounts.card), repository: repository, dataVersion: dataVersion)

        #expect(editor.title == "編輯信用卡")
        #expect(editor.name == "iOS 測試信用卡")
        #expect(editor.amountText == "12000")
        #expect(editor.unbilledText == "3500")
        #expect(editor.creditLimitText == "100000")
        #expect(editor.statementDay == 15)
        #expect(editor.paymentDueDay == 5)
        #expect(editor.colorHex == "#FFD4A0")
        #expect(!editor.canChangeKind)

        editor.kind = .bank
        #expect(editor.kind == .creditCard)
    }

    @Test("名稱去掉前後空白後是空的，提示「請輸入帳戶名稱」,不送出")
    func nameIsRequired() async {
        let editor = adding(.bank)
        editor.name = "   "

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入帳戶名稱")
        #expect(await repository.createdDrafts.isEmpty)
        #expect(dataVersion.value == 0)
    }

    @Test("新增成功後資料版本遞增，其他畫面才會重新抓資料")
    func creatingBumpsDataVersion() async {
        let editor = adding(.creditCard)
        editor.name = "  旅遊卡  "
        editor.amountText = "1200"
        editor.unbilledText = "300"
        editor.creditLimitText = ""

        #expect(await editor.save())

        #expect(dataVersion.value == 1)
        #expect(await repository.createdDrafts == [.creditCard(CreditCardDraft(
            name: "旅遊卡",
            colorHex: "#95E1D3",
            billedDebt: Money(1200),
            unbilledDebt: Money(300),
            creditLimit: nil,
            statementDay: 15,
            paymentDueDay: 5
        ))])
    }

    @Test("新增銀行存款帳戶時可以設為家庭共同基金，預設不是")
    func addingJointFund() async {
        let editor = adding(.bank)
        #expect(!editor.isJointFund)
        editor.name = "家庭共同基金"
        editor.isJointFund = true

        #expect(await editor.save())

        #expect(await repository.createdDrafts == [.bank(BankAccountDraft(
            name: "家庭共同基金", colorHex: "#95E1D3", balance: .zero, isJointFund: true
        ))])
    }

    @Test("編輯家庭共同基金帳戶時，保留原本的標記")
    func editingKeepsJointFundFlag() async {
        let joint = BankAccount(
            id: AccountID("joint"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true
        )
        let editor = AccountEditorModel(editing: .bank(joint), repository: repository, dataVersion: dataVersion)
        editor.amountText = "9000"

        #expect(await editor.save())

        #expect(await repository.updatedDrafts == [AccountID("joint"): .bank(BankAccountDraft(
            name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(9000), isJointFund: true
        ))])
        #expect(dataVersion.value == 1)
    }

    @Test("金額不是數字時當作 0(跟 web 的 parseFloat || 0 一樣)")
    func invalidAmountIsZero() async {
        let editor = adding(.bank)
        editor.name = "零用金"
        editor.amountText = "abc"

        #expect(await editor.save())

        #expect(await repository.createdDrafts.first == .bank(BankAccountDraft(
            name: "零用金", colorHex: "#95E1D3", balance: Money(0), isJointFund: false
        )))
    }

    @Test("儲存失敗時顯示後端的訊息，資料版本不變")
    func failureShowsMessage() async {
        await repository.fail(with: .rejected("請填寫帳戶名稱和類型"))
        let editor = adding(.bank)
        editor.name = "零用金"

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請填寫帳戶名稱和類型")
        #expect(dataVersion.value == 0)
    }
}
