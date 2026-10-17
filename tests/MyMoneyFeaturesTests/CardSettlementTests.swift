import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("結帳日出帳作業")
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

    @Test("有結帳日、或有已出帳或未出帳的款項就能打開出帳作業(預覽可以重複檢視，出帳過一次按鈕也不會消失;上游 ADR 0024);都沒有時不能")
    func showsRolloverWithStatementDayOrDebt() async {
        let (model, _) = await loaded(today: 1)
        #expect(model.creditCards.map(model.showsRollover) == [true, true])

        func card(billed: Int, unbilled: Int, statementDay: Int?) -> CreditCard {
            CreditCard(
                id: AccountID("c"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)),
                unbilledDebt: Money(Decimal(unbilled)), creditLimit: nil, statementDay: statementDay, paymentDueDay: 5
            )
        }
        #expect(model.showsRollover(card(billed: 5000, unbilled: 0, statementDay: 15)), "已出帳、未出帳都是 0，有結帳日也能再檢視")
        #expect(model.showsRollover(card(billed: 5000, unbilled: 0, statementDay: nil)))
        #expect(!model.showsRollover(card(billed: 0, unbilled: 0, statementDay: nil)))
    }

    @Test("長按選單的出帳作業:沒設結帳日的卡要先請使用者設定結帳日")
    func rolloverNeedsStatementDay() async {
        let (model, _) = await loaded(today: 28)
        let bare = CreditCard(
            id: AccountID("bare"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(500), unbilledDebt: .zero,
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )
        #expect(model.rolloverNeedsStatementDay(for: bare))
        #expect(model.creditCards.map(model.rolloverNeedsStatementDay) == [false, false])
    }

    @Test("長按選單的出帳作業:打開預覽 sheet,確認後送出延期的明細，資料版本遞增")
    func rollOverFromTheAccountsList() async throws {
        let (model, repository) = await loaded(today: 28)
        let card = try #require(model.creditCards.first)

        let rollover = model.makeStatementRollover(for: card)
        await rollover.load()
        #expect(rollover.deferredCount == 1, "開窗時已延至下期的那一筆")
        let message = await rollover.submit()

        #expect(await repository.rolledOverIDs == [card.id])
        #expect(message?.hasPrefix("帳單出帳作業完成！") == true)
        #expect(dataVersion.value == 1)
    }
}

@MainActor
@Suite("信用卡未出帳自動校準")
struct ReconcileUnbilledTests {
    private let dataVersion = DataVersion()

    /// 校準只在信用卡詳細頁(#73),帳戶頁的長按選單沒有。
    private func detail(_ card: CreditCard, repository: InMemoryAccountRepository) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: [SampleAccounts.savings], loadedVersion: dataVersion.value, scope: .all,
            repository: repository, dataVersion: dataVersion
        )
    }

    @Test("確認文字照 web 用正名，再說明重算的期間、會扣掉刷退和還款實際沖到未出帳款的部分;後端已修好，不再提醒未出帳款會被算少(上游 97f4789)")
    func confirmationExplainsPeriodAndConsequence() {
        let repository = InMemoryAccountRepository.sample()

        #expect(detail(SampleAccounts.card, repository: repository).reconcileConfirmation
            == "確定要依據「iOS 測試信用卡」的當期消費明細，自動校準未出帳款嗎？"
            + "會重算還沒出帳的消費（過了結帳日、還沒按「出帳作業」的那一期也算在內），加上延至下期的消費，並扣掉這段期間的刷退。")

        let withoutStatementDay = CreditCard(
            id: AccountID("no-statement-day"), name: "沒有結帳日的卡", colorHex: "#FFD4A0", billedDebt: .zero, unbilledDebt: .zero,
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )
        #expect(detail(withoutStatementDay, repository: repository).reconcileConfirmation
            == "確定要依據「沒有結帳日的卡」的當期消費明細，自動校準未出帳款嗎？"
            + "會重算所有還沒出帳的消費，並扣掉這段期間的刷退。")
        #expect(
            !detail(SampleAccounts.card, repository: repository).reconcileConfirmation.contains("還款"),
            "新的校準不再扣還款沖掉的部分(上游 ADR 0020)"
        )

        #expect(!detail(SampleAccounts.card, repository: repository).reconcileConfirmation.contains("會被算少"))
    }

    @Test("確認後校準，顯示後端的訊息，資料版本遞增;送出期間是校準中", .timeLimit(.minutes(1)))
    func reconcile() async {
        let gate = Gate()
        let repository = InMemoryAccountRepository.sample(gate: gate)
        let model = detail(SampleAccounts.card, repository: repository)

        let reconciling = Task { await model.reconcile() }
        await gate.waitUntilReached()
        #expect(model.isReconciling)
        await gate.open()
        await reconciling.value

        #expect(!model.isReconciling)
        #expect(await repository.reconciledIDs == [SampleAccounts.card.id])
        #expect(model.noticeMessage == "已自動校準「iOS 測試信用卡」未出帳金額為 NT$ 3,500")
        #expect(dataVersion.value == 1)
    }

    @Test("校準失敗時顯示後端的錯誤，資料版本不變")
    func reconcileFailure() async {
        let repository = InMemoryAccountRepository.sample()
        await repository.fail(with: .rejected("信用卡不存在或無權限"))
        let model = detail(SampleAccounts.card, repository: repository)

        await model.reconcile()

        #expect(model.alertMessage == "信用卡不存在或無權限")
        #expect(model.noticeMessage == nil)
        #expect(dataVersion.value == 0)
    }
}

@MainActor
@Suite("信用卡扣款還款")
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

    @Test("可用餘額：顯示扣款帳戶的餘額，換扣款帳戶就跟著換;沒選時沒有(#78)")
    func availableBalance() {
        let model = payment(card())

        #expect(model.availableBalance == nil, "還沒選扣款帳戶，不該有可用餘額")
        model.bankAccountID = salary.id
        #expect(model.availableBalance == salary.balance)
        model.bankAccountID = joint.id
        #expect(model.availableBalance == joint.balance)
        model.bankAccountID = nil
        #expect(model.availableBalance == nil)
    }

    @Test("從「繳款」的三個項目打開，帶入不同的金額、歸屬與備註(web 的 handleOpenPay,備註照上游 97f4789 的寫法:半形括號、括號前有空格)", arguments: [
        (CardPaymentModel.Preset.shared, "3000", true, "扣繳【iOS 測試信用卡】卡費 (家庭公帳代墊)"),
        (CardPaymentModel.Preset.personal, "16380", false, "扣繳【iOS 測試信用卡】卡費 (個人私帳)"),
        (CardPaymentModel.Preset.full, "19380", true, "扣繳【iOS 測試信用卡】卡費 (全額)"),
    ])
    func presets(preset: CardPaymentModel.Preset, amount: String, isShared: Bool, note: String) {
        let model = payment(card(), preset: preset)

        #expect(model.amountText == amount)
        #expect(model.isShared == isShared)
        #expect(model.note == note)
        #expect(model.date == today)
        // 扣款帳戶是空的:不再預設「第一個餘額大於 0 的活存帳戶」(上游 ADR 0011，#112)。
        #expect(model.bankAccountID == nil)
    }

    @Test("預設金額是 0 時留空")
    func zeroPresetAmountIsEmpty() {
        #expect(payment(card(shared: 0, personal: 19380), preset: .shared).amountText == "")
    }

    @Test("沒綁定預設扣款帳戶時扣款帳戶是空的:不論活存帳戶有沒有餘額，都不預選(綁定時帶入,見 PaymentAccountPrefillTests)")
    func bankAccountIsNeverPreselected() {
        #expect(payment(card(), banks: [empty]).bankAccountID == nil)
        #expect(payment(card(), banks: [salary, joint]).bankAccountID == nil)
    }

    @Test("驗證：沒選扣款帳戶、金額無效、超過信用卡待繳總額", arguments: [
        (false, "3000", "請選擇扣款銀行帳戶"),
        (true, "0", "請輸入有效的繳款金額"),
        (true, "abc", "請輸入有效的繳款金額"),
        (true, "1,000", "請輸入有效的繳款金額"),
        (true, "12.5", "請輸入有效的繳款金額"),
        (true, "19381", "繳款金額不可超過信用卡待繳總額 $19,380"),
    ])
    func validation(hasBank: Bool, amount: String, message: String) async {
        let repository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
        let model = payment(card(), repository: repository)
        model.bankAccountID = hasBank ? salary.id : nil
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

    @Test("成功後送出所選的內容，資料版本遞增;扣款帳戶只列出活存帳戶")
    func pay() async {
        let repository = InMemoryAccountRepository(accounts: [], summary: SampleAccounts.summary)
        let model = payment(card(), preset: .shared, repository: repository)
        model.bankAccountID = joint.id

        #expect(await model.submit() == .paid)

        #expect(await repository.payments == [CardPayment(
            bankAccountID: joint.id, creditCardID: AccountID("card"), amount: Money(3000), date: today,
            note: "扣繳【iOS 測試信用卡】卡費 (家庭公帳代墊)", isShared: true
        )])
        #expect(dataVersion.value == 1)
        #expect(model.bankAccounts.map(\.id) == [empty.id, salary.id, joint.id])
    }
}
