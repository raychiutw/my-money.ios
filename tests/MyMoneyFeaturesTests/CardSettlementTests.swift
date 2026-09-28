import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("結帳日出帳結轉")
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

    @Test("有未出帳金額就能結轉，不看結帳日(web 在 82d9124 拿掉了結帳日的條件);沒有未出帳金額時不能結轉")
    func showsRolloverWheneverUnbilled() async {
        let (model, _) = await loaded(today: 1)
        #expect(model.creditCards.map(model.showsRollover) == [true, true])

        let settled = CreditCard(
            id: AccountID("settled"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(5000), unbilledDebt: .zero,
            creditLimit: nil, statementDay: 15, paymentDueDay: 5
        )
        #expect(!model.showsRollover(settled))
    }

    @Test("確認後結轉，顯示後端的訊息，資料版本遞增")
    func rollOver() async throws {
        let (model, repository) = await loaded(today: 28)
        let card = try #require(model.creditCards.first)

        #expect(model.rolloverConfirmation(for: card) == "確定要將「iOS 測試信用卡」的未出帳金額 $3,500 結轉為本期已出帳待繳嗎？")
        #expect(model.rolloverReminder(for: card) == "未出帳 $3,500,可結轉為本期已出帳待繳")
        await model.rollOver(card)

        #expect(await repository.rolledOverIDs == [card.id])
        #expect(model.noticeMessage == "已將未出帳 $3,500 成功結轉為已出帳待繳！")
        #expect(dataVersion.value == 1)
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
        preset: CardPaymentModel.Preset = .full,
        banks: [BankAccount]? = nil,
        repository: InMemoryAccountRepository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
    ) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: banks ?? [empty, salary, joint], repository: repository,
            dataVersion: dataVersion, today: { today }
        )
    }

    @Test("從卡片的三個按鈕打開，帶入不同的金額、歸屬與備註(web 的 handleOpenPay)", arguments: [
        (CardPaymentModel.Preset.shared, "3000", true, "繳納 iOS 測試信用卡 卡費 (家庭代墊)"),
        (CardPaymentModel.Preset.personal, "16380", false, "繳納 iOS 測試信用卡 卡費 (個人私帳)"),
        (CardPaymentModel.Preset.full, "19380", true, "繳納 iOS 測試信用卡 卡費 (全額)"),
    ])
    func presets(preset: CardPaymentModel.Preset, amount: String, isShared: Bool, note: String) {
        let model = payment(card(), preset: preset)

        #expect(model.amountText == amount)
        #expect(model.isShared == isShared)
        #expect(model.note == note)
        #expect(model.date == today)
        // 扣款帳戶一律是第一個餘額大於 0 的銀行存款帳戶(web 不再自動改選家庭共同基金)。
        #expect(model.bankAccountID == salary.id)
    }

    @Test("預設金額是 0 時留空")
    func zeroPresetAmountIsEmpty() {
        #expect(payment(card(shared: 0, personal: 19380), preset: .shared).amountText == "")
    }

    @Test("沒有任何餘額大於 0 的銀行存款帳戶時，預設第一個")
    func defaultsToFirstBank() {
        #expect(payment(card(), banks: [empty]).bankAccountID == empty.id)
    }

    @Test("驗證：沒選扣款帳戶、金額無效、超過待繳卡費總額", arguments: [
        (false, "3000", "請選擇扣款銀行帳戶"),
        (true, "0", "請輸入大於 0 的繳款金額"),
        (true, "abc", "請輸入大於 0 的繳款金額"),
        (true, "1,000", "請輸入大於 0 的繳款金額"),
        (true, "12.5", "請輸入大於 0 的繳款金額"),
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
        let model = payment(card(), preset: .shared, repository: repository)
        model.bankAccountID = joint.id

        #expect(await model.submit() == .paid)

        #expect(await repository.payments == [CardPayment(
            bankAccountID: joint.id, creditCardID: AccountID("card"), amount: Money(3000), date: today,
            note: "繳納 iOS 測試信用卡 卡費 (家庭代墊)", isShared: true
        )])
        #expect(dataVersion.value == 1)
        #expect(model.bankAccounts.map(\.id) == [empty.id, salary.id, joint.id])
    }
}
