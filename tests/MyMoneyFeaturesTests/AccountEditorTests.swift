import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("資產帳戶的新增與編輯")
struct AccountEditorTests {
    private let repository = InMemoryAccountRepository(accounts: [], summary: .zero)
    private let dataVersion = DataVersion()

    private func adding(_ kind: AccountKind) -> AccountEditorModel {
        AccountEditorModel(adding: kind, repository: repository, dataVersion: dataVersion, randomColor: { "#95E1D3" })
    }

    @Test("新增活存帳戶的預設值：餘額空白(存成 0)、沒有信用卡欄位、隨機代表色")
    func bankDefaults() {
        let editor = adding(.bank)

        #expect(editor.title == "新增活存帳戶")
        #expect(editor.amountLabel == "餘額")
        #expect(editor.amountText == "")
        #expect(editor.creditLimitText == "")
        #expect(editor.statementDay == nil)
        #expect(editor.paymentDueDay == nil)
        #expect(editor.colorHex == "#95E1D3")
        #expect(editor.canChangeKind)
    }

    @Test("新增現金的代表色預設是綠色 #10B981(web 的 openAdd);切到其他類型改回隨機挑的顏色")
    func cashWalletDefaultColor() {
        let editor = adding(.cash)
        #expect(editor.colorHex == "#10B981")

        editor.kind = .bank
        #expect(editor.colorHex == "#95E1D3")
        editor.kind = .cash
        #expect(editor.colorHex == "#10B981")
    }

    @Test("新增信用卡的預設值：不輸入已出帳待繳款(web 拿掉了)、未出帳款欄空白(存成 0)、額度 100000、結帳日 15、繳款日 5")
    func creditCardDefaults() {
        let editor = adding(.creditCard)

        #expect(editor.title == "新增信用卡")
        #expect(!editor.showsAmountField)
        #expect(editor.unbilledLabel == "未出帳款")
        #expect(editor.unbilledText == "")
        #expect(editor.creditLimitText == "100000")
        #expect(editor.statementDay == 15)
        #expect(editor.paymentDueDay == 5)
    }

    @Test("新增時從信用卡切到活存帳戶，不會把信用卡的額度與日期存進去")
    func switchingToBankDropsCardFields() async {
        let editor = adding(.creditCard)
        editor.name = "薪轉戶"

        editor.kind = .bank
        #expect(await editor.save())

        #expect(await repository.createdDrafts == [.bank(BankAccountDraft(
            name: "薪轉戶", colorHex: "#95E1D3", balance: Money(0), isJointFund: false
        ))])
    }

    @Test("新增時從活存帳戶切到信用卡，套用信用卡的預設值")
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
        #expect(!editor.showsAmountField)
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
        editor.unbilledText = "300"
        editor.creditLimitText = ""

        #expect(await editor.save())

        #expect(dataVersion.value == 1)
        #expect(await repository.createdDrafts == [.creditCard(CreditCardDraft(
            name: "旅遊卡",
            colorHex: "#95E1D3",
            billedDebt: .zero,
            unbilledDebt: Money(300),
            creditLimit: nil,
            statementDay: 15,
            paymentDueDay: 5,
            paymentAccount: .none  // 新增時沒選預設扣款帳戶:明確的「不綁定」
        ))])
    }

    @Test("新增現金：標題、金額欄是「目前現金餘額」,預設個人私帳，送出現金")
    func addingCashWallet() async {
        let editor = adding(.cash)
        #expect(editor.title == "新增現金")
        #expect(editor.showsAmountField)
        #expect(editor.amountLabel == "目前現金餘額")
        #expect(!editor.isJointFund)
        editor.name = "我的皮夾"
        editor.amountText = "800"

        #expect(await editor.save())

        #expect(await repository.createdDrafts == [.cash(CashWalletDraft(
            name: "我的皮夾", colorHex: "#10B981", balance: Money(800), isJointFund: false
        ))])
    }

    @Test("編輯歸屬家庭共同基金的現金：帶入原值、不能改類型，送出現金並保留家庭共同基金")
    func editingCashWallet() async {
        let jar = CashWallet(id: AccountID("jar"), name: "客廳零用金盒", colorHex: "#10B981", balance: Money(2000), isJointFund: true)
        let editor = AccountEditorModel(editing: .cash(jar), repository: repository, dataVersion: dataVersion)
        #expect(editor.title == "編輯現金")
        #expect(editor.amountText == "2000")
        #expect(editor.isJointFund)
        #expect(!editor.canChangeKind)
        editor.amountText = "1800"

        #expect(await editor.save())

        #expect(await repository.updatedDrafts == [AccountID("jar"): .cash(CashWalletDraft(
            name: "客廳零用金盒", colorHex: "#10B981", balance: Money(1800), isJointFund: true
        ))])
    }

    @Test("信用卡也能設成家庭信用卡(所有類型都能設歸屬)")
    func creditCardCanBeHouseholdCard() async {
        let editor = adding(.creditCard)
        editor.name = "家庭卡"
        editor.isJointFund = true

        #expect(await editor.save())

        guard case .creditCard(let card)? = await repository.createdDrafts.first else {
            Issue.record("沒有送出信用卡")
            return
        }
        #expect(card.isJointFund)
    }

    @Test("編輯信用卡時照原值送回已出帳待繳款(表單不能改)")
    func editingCardKeepsBilledDebt() async {
        let editor = AccountEditorModel(editing: .creditCard(SampleAccounts.card), repository: repository, dataVersion: dataVersion)
        editor.unbilledText = "4000"

        #expect(await editor.save())

        guard case .creditCard(let card)? = await repository.updatedDrafts[SampleAccounts.card.id] else {
            Issue.record("沒有送出信用卡")
            return
        }
        #expect(card.billedDebt == Money(12000))
        #expect(card.unbilledDebt == Money(4000))
    }

    @Test("歸屬的選項是「私帳」和「公帳」,所有類型都一樣(上游 ADR 0014，#138)", arguments: [AccountKind.cash, .bank, .creditCard])
    func ownershipChoicesAreSharedAndPrivate(kind: AccountKind) {
        let editor = adding(kind)

        #expect(editor.ownershipChoices.map(\.title) == ["個人私帳", "家庭公帳"])
        #expect(editor.ownershipChoices.map(\.isJointFund) == [false, true])
    }

    @Test("新增時切換類型，歸屬選項不變，已選的歸屬也不變")
    func ownershipChoicesFollowKindSwitch() {
        let editor = adding(.bank)
        editor.isJointFund = true

        editor.kind = .creditCard

        #expect(editor.ownershipChoices.map(\.title) == ["個人私帳", "家庭公帳"])
        #expect(editor.isJointFund)
    }

    @Test("新增活存帳戶時可以設為家庭共同基金，預設不是")
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

    // MARK: 預設扣款帳戶(上游 `3d09060`)

    private let savings = BankAccount(
        id: AccountID("bank-1"), name: "iOS 測試存款", colorHex: "#A8D8EA", balance: Money(50000), isJointFund: false
    )
    private let otherBank = BankAccount(
        id: AccountID("bank-2"), name: "iOS 家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true
    )

    private func boundCard(to bank: AccountID?, name: String? = nil) -> CreditCard {
        CreditCard(
            id: AccountID("card-1"), name: "iOS 暫存卡", colorHex: "#FFD4A0", billedDebt: Money(3000), unbilledDebt: Money(500),
            creditLimit: Money(50000), statementDay: 15, paymentDueDay: 5, paymentAccountID: bank, paymentAccountName: name
        )
    }

    private func editing(_ card: CreditCard, banks: [BankAccount]? = nil, repository: InMemoryAccountRepository? = nil) -> AccountEditorModel {
        AccountEditorModel(
            editing: .creditCard(card), bankAccounts: banks ?? [savings, otherBank], repository: repository ?? self.repository,
            dataVersion: dataVersion
        )
    }

    @Test("信用卡編輯器的預設扣款帳戶:選項是傳進來的活存帳戶;新增時預設沒綁定;現金與活存帳戶沒有這一列")
    func paymentAccountOptions() {
        let card = AccountEditorModel(
            adding: .creditCard, bankAccounts: [savings, otherBank], repository: repository, dataVersion: dataVersion,
            randomColor: { "#95E1D3" }
        )
        #expect(card.showsPaymentAccount)
        #expect(card.paymentAccountID == nil)
        #expect(card.paymentAccountOptions.map(\.name) == ["iOS 測試存款", "iOS 家庭共同基金"])

        card.kind = .bank
        #expect(!card.showsPaymentAccount)
    }

    @Test("編輯綁定的信用卡:帶入原本的綁定;只改名稱儲存,綁定仍在")
    func editingKeepsThePaymentAccount() async throws {
        let repository = InMemoryAccountRepository(accounts: [.creditCard(boundCard(to: savings.id, name: savings.name))], summary: .zero)
        let editor = editing(boundCard(to: savings.id, name: savings.name), repository: repository)
        #expect(editor.paymentAccountID == savings.id)

        editor.name = "改個名字"
        #expect(await editor.save())

        guard case .creditCard(let draft)? = await repository.updatedDrafts[AccountID("card-1")] else {
            Issue.record("沒有送出編輯")
            return
        }
        #expect(draft.paymentAccount == .unchanged, "只改名稱:沒動過綁定,不送這個欄位(後端保留原值)")
    }

    @Test("更換與清除預設扣款帳戶:送出的內容跟著變")
    func changingAndClearingThePaymentAccount() async throws {
        let repository = InMemoryAccountRepository(accounts: [.creditCard(boundCard(to: savings.id, name: savings.name))], summary: .zero)
        let editor = editing(boundCard(to: savings.id, name: savings.name), repository: repository)

        editor.paymentAccountID = otherBank.id
        #expect(await editor.save())
        guard case .creditCard(let changed)? = await repository.updatedDrafts[AccountID("card-1")] else { return }
        #expect(changed.paymentAccount == .bank(otherBank.id))

        editor.paymentAccountID = nil
        #expect(await editor.save())
        guard case .creditCard(let cleared)? = await repository.updatedDrafts[AccountID("card-1")] else { return }
        #expect(cleared.paymentAccount == .none, "使用者清除:送明確的 null")
    }

    @Test("綁定的活存帳戶不在選項裡(被刪除,或帳戶範圍看不到):編輯器顯示成沒綁定,但使用者沒動它儲存時**不送這個欄位**,不會把看不到的綁定清掉")
    func bindingOutsideTheOptionsIsPreservedWhenUntouched() async throws {
        let outOfScope = boundCard(to: savings.id, name: savings.name)
        let repository = InMemoryAccountRepository(accounts: [.creditCard(outOfScope)], summary: .zero)
        let editor = editing(outOfScope, banks: [otherBank], repository: repository)
        #expect(editor.paymentAccountID == nil, "選項裡沒有它,畫面顯示成不綁定")

        editor.name = "只改名稱"
        #expect(await editor.save())

        guard case .creditCard(let draft)? = await repository.updatedDrafts[AccountID("card-1")] else { return }
        #expect(draft.paymentAccount == .unchanged)
    }

    @Test("懸空的綁定(活存帳戶已刪除)同樣沒動就不送;使用者選了別的帳戶才送新的,選「不綁定」才送 null")
    func danglingBindingFollowsTheUsersChoice() async throws {
        let dangling = boundCard(to: AccountID("deleted-bank"), name: nil)
        let repository = InMemoryAccountRepository(accounts: [.creditCard(dangling)], summary: .zero)
        let editor = editing(dangling, repository: repository)
        #expect(editor.paymentAccountID == nil)

        #expect(await editor.save())
        guard case .creditCard(let untouched)? = await repository.updatedDrafts[AccountID("card-1")] else { return }
        #expect(untouched.paymentAccount == .unchanged)

        editor.paymentAccountID = savings.id
        #expect(await editor.save())
        guard case .creditCard(let chosen)? = await repository.updatedDrafts[AccountID("card-1")] else { return }
        #expect(chosen.paymentAccount == .bank(savings.id))
    }

    @Test("新增信用卡:沒選預設扣款帳戶就是明確的「不綁定」,選了就送那個帳戶")
    func addingSendsTheChoice() async throws {
        let repository = InMemoryAccountRepository(accounts: [.bank(savings)], summary: .zero)
        let editor = AccountEditorModel(
            adding: .creditCard, bankAccounts: [savings], repository: repository, dataVersion: dataVersion, randomColor: { "#95E1D3" }
        )
        editor.name = "新卡"
        #expect(await editor.save())
        guard case .creditCard(let none)? = await repository.createdDrafts.last else { return }
        #expect(none.paymentAccount == .none)

        editor.paymentAccountID = savings.id
        #expect(await editor.save())
        guard case .creditCard(let bound)? = await repository.createdDrafts.last else { return }
        #expect(bound.paymentAccount == .bank(savings.id))
    }
}
