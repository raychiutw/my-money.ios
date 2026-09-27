import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("結帳日出帳結轉與欠款公私拆解")
struct StatementRolloverTests {
    private let dataVersion = DataVersion()

    private func loaded(today: Int) async -> (AccountsModel, InMemoryAccountRepository) {
        let repository = InMemoryAccountRepository.sample()
        let model = AccountsModel(
            repository: repository, dataVersion: dataVersion, today: { CalendarDay(year: 2026, month: 9, day: today) }
        )
        await model.load()
        return (model, repository)
    }

    @Test("今天(台灣時間)到了結帳日才提醒")
    func showsRolloverFromStatementDay() async {
        let (before, _) = await loaded(today: 14)
        #expect(before.creditCards.map(before.showsRollover) == [false, true])

        let (after, _) = await loaded(today: 15)
        #expect(after.creditCards.map(after.showsRollover) == [true, true])
    }

    @Test("確認後結轉，顯示後端的訊息，資料版本遞增")
    func rollOver() async throws {
        let (model, repository) = await loaded(today: 28)
        let card = try #require(model.creditCards.first)

        #expect(model.rolloverConfirmation(for: card) == "確定要將「iOS 測試信用卡」的未出帳金額 $3,500 結轉為本期已出帳待繳嗎？")
        #expect(model.rolloverReminder(for: card) == "每月 15 號結帳日已過，有未出帳金額待結轉")
        await model.rollOver(card)

        #expect(await repository.rolledOverIDs == [card.id])
        #expect(model.noticeMessage == "已將未出帳 $3,500 成功結轉為已出帳待繳！")
        #expect(dataVersion.value == 1)
    }

    @Test("欠款公私拆解：家庭公帳的佔比取整數")
    func debtSplit() {
        let card = CreditCard(
            id: AccountID("card"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(12000), unbilledDebt: Money(7380),
            creditLimit: nil, statementDay: 15, paymentDueDay: 5, sharedDebt: Money(3000), personalDebt: Money(16380)
        )

        // 3000 / 19380 = 15.48%。
        #expect(card.sharedDebtPercentText == "15%")
    }
}

@MainActor
@Suite("信用卡還款沖銷")
struct CardPaymentTests {
    private let dataVersion = DataVersion()
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private let empty = BankAccount(id: AccountID("empty"), name: "空的帳戶", colorHex: "#A8D8EA", balance: .zero, isJointFund: false)
    private let salary = BankAccount(id: AccountID("salary"), name: "薪轉戶", colorHex: "#A8D8EA", balance: Money(2000), isJointFund: false)
    private let joint = BankAccount(id: AccountID("joint"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(50000), isJointFund: true)

    private func card(billed: Int = 12000, unbilled: Int = 7380, shared: Int = 3000, personal: Int = 16380) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "iOS 測試信用卡", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)),
            unbilledDebt: Money(Decimal(unbilled)), creditLimit: nil, statementDay: 15, paymentDueDay: 5,
            sharedDebt: Money(Decimal(shared)), personalDebt: Money(Decimal(personal))
        )
    }

    private func payment(
        _ card: CreditCard,
        banks: [BankAccount]? = nil,
        repository: InMemoryAccountRepository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
    ) -> CardPaymentModel {
        CardPaymentModel(
            card: card, bankAccounts: banks ?? [empty, salary, joint], repository: repository, dataVersion: dataVersion,
            today: { today }
        )
    }

    @Test("預設值：第一個餘額大於 0 的銀行存款帳戶、已出帳待繳金額、今天、備註、依公私佔比決定歸屬")
    func defaults() {
        let model = payment(card())

        #expect(model.bankAccountID == salary.id)
        #expect(model.amountText == "12000")
        #expect(model.date == today)
        #expect(model.note == "繳納【iOS 測試信用卡】卡費")
        #expect(!model.isShared)
    }

    @Test("沒有已出帳待繳金額時，預設金額是未出帳金額;公帳部分較多時預設家庭公帳")
    func defaultsWithoutBilledDebt() {
        let model = payment(card(billed: 0, unbilled: 7380, shared: 5000, personal: 2380))

        #expect(model.amountText == "7380")
        #expect(model.isShared)
    }

    @Test("公帳部分和私帳部分一樣多時，預設家庭公帳(跟 web 的 >= 一樣)")
    func equalSplitDefaultsToShared() {
        #expect(payment(card(shared: 5000, personal: 5000)).isShared)
    }

    @Test("沒有任何餘額大於 0 的銀行存款帳戶時，預設第一個")
    func defaultsToFirstBank() {
        #expect(payment(card(), banks: [empty]).bankAccountID == empty.id)
    }

    @Test("「繳家庭代墊」帶入公帳金額並優先選家庭共同基金;「繳個人私帳」帶入私帳金額並優先選非共同基金的帳戶")
    func quickFills() {
        let model = payment(card())

        #expect(model.sharedQuickFillTitle == "繳家庭代墊 $3,000")
        model.fillShared()
        #expect(model.amountText == "3000")
        #expect(model.bankAccountID == joint.id)
        #expect(model.isShared)

        #expect(model.personalQuickFillTitle == "繳個人私帳 $16,380")
        model.fillPersonal()
        #expect(model.amountText == "16380")
        #expect(model.bankAccountID == empty.id)
        #expect(!model.isShared)
    }

    @Test("金額是 0 的快捷按鈕不顯示")
    func quickFillsHiddenWhenZero() {
        let model = payment(card(shared: 0, personal: 19380))

        #expect(model.sharedQuickFillTitle == nil)
        #expect(model.personalQuickFillTitle != nil)
    }

    @Test("驗證：沒選扣款帳戶、金額無效、超過待繳卡費總額", arguments: [
        (false, "3000", "請選擇扣款銀行帳戶"),
        (true, "0", "請輸入大於 0 的繳款金額"),
        (true, "abc", "請輸入大於 0 的繳款金額"),
        (true, "19381", "繳款金額不可超過當前待繳總額 $19,380"),
    ])
    func validation(hasBank: Bool, amount: String, message: String) async {
        let repository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
        let model = payment(card(), repository: repository)
        if !hasBank { model.bankAccountID = nil }
        model.amountText = amount

        #expect(await model.submit() == .invalid)

        #expect(model.errorMessage == message)
        #expect(await repository.payments.isEmpty)
    }

    @Test("扣款帳戶的餘額小於繳款金額時，要先確認才能繼續")
    func lowBalanceNeedsConfirmation() async throws {
        let repository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
        let model = payment(card(), repository: repository)
        model.bankAccountID = salary.id
        model.amountText = "3000"

        #expect(await model.submit() == .needsConfirmation)
        #expect(model.lowBalanceConfirmation == "扣款帳戶「薪轉戶」目前餘額是 $2,000,小於繳款金額 $3,000。確定仍要繼續扣款嗎？")
        #expect(await repository.payments.isEmpty)

        #expect(await model.submit(confirmedLowBalance: true) == .paid)
        #expect(await repository.payments.count == 1)
    }

    @Test("成功後送出所選的內容，資料版本遞增;扣款帳戶只列出銀行存款帳戶")
    func pay() async {
        let repository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
        let model = payment(card(), repository: repository)
        model.fillShared()

        #expect(await model.submit() == .paid)

        #expect(await repository.payments == [CardPayment(
            bankAccountID: joint.id, creditCardID: AccountID("card"), amount: Money(3000), date: today,
            note: "繳納【iOS 測試信用卡】卡費", isShared: true
        )])
        #expect(dataVersion.value == 1)
        #expect(model.bankAccounts.map(\.id) == [empty.id, salary.id, joint.id])
    }
}
