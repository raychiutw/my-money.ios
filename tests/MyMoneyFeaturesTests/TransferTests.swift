import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("ATM 提款／帳戶互轉")
struct TransferTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let dataVersion = DataVersion()

    private func loaded(
        _ repository: InMemoryAccountRepository = .sampleWithCash(),
        from: AccountID? = nil,
        to: AccountID? = nil
    ) async -> TransferModel {
        let model = TransferModel(
            repository: repository, dataVersion: dataVersion, today: { today }, preferredFrom: from, preferredTo: to
        )
        await model.load()
        return model
    }

    @Test("從帳戶頁最上面的入口打開:轉出與轉入都是空的(上游 ADR 0011，#111);信用卡不在可選的帳戶裡")
    func defaults() async {
        let model = await loaded()

        #expect(model.fromAccountID == nil, "不該預選第一個活存帳戶")
        #expect(model.toAccountID == nil, "不該預選第一個現金")
        #expect(model.candidates.map(\.name) == ["iOS 測試皮夾", "iOS 測試存款"])
        #expect(model.date == today)
        #expect(model.amountText == "")
    }

    @Test("可用餘額：顯示轉出帳戶的餘額，換轉出帳戶就跟著換;沒選轉出帳戶時沒有(#78)")
    func availableBalance() async {
        let model = await loaded()

        #expect(model.availableBalance == nil, "還沒選轉出帳戶，不該有可用餘額")
        model.fromAccountID = SampleAccounts.savings.id
        #expect(model.availableBalance == SampleAccounts.savings.balance)
        model.fromAccountID = SampleAccounts.wallet.id
        #expect(model.availableBalance == SampleAccounts.wallet.balance)
        model.fromAccountID = nil
        #expect(model.availableBalance == nil)
    }

    @Test("從現金的「ATM 提款」打開：只帶入轉入(這個現金)，轉出是空的;從活存帳戶的「轉帳／提款」打開：只帶入轉出，轉入是空的")
    func openedFromAnAccount() async {
        let fromWallet = await loaded(to: SampleAccounts.wallet.id)
        #expect(fromWallet.toAccountID == SampleAccounts.wallet.id)
        #expect(fromWallet.fromAccountID == nil)

        let fromBank = await loaded(from: SampleAccounts.savings.id)
        #expect(fromBank.fromAccountID == SampleAccounts.savings.id)
        #expect(fromBank.toAccountID == nil)
    }

    @Test("開窗時轉出與轉入是同一個帳戶:轉入清成空(上游開窗時的處理)")
    func sameAccountOnOpenClearsTheTarget() async {
        let model = await loaded(from: SampleAccounts.wallet.id, to: SampleAccounts.wallet.id)

        #expect(model.fromAccountID == SampleAccounts.wallet.id)
        #expect(model.toAccountID == nil)
    }

    @Test("轉入的選項不含已選的轉出帳戶")
    func toCandidatesExcludeFrom() async {
        let model = await loaded(from: SampleAccounts.savings.id)

        #expect(model.toCandidates.map(\.name) == ["iOS 測試皮夾"])
    }

    @Test("快捷情境:ATM 提款至皮夾、存款至銀行，帶入帳戶與備註")
    func quickScenarios() async {
        let model = await loaded()

        model.applyDepositScenario()
        #expect(model.fromAccountID == SampleAccounts.wallet.id)
        #expect(model.toAccountID == SampleAccounts.savings.id)
        #expect(model.note == "存入現金至銀行")

        model.applyATMScenario()
        #expect(model.fromAccountID == SampleAccounts.savings.id)
        #expect(model.toAccountID == SampleAccounts.wallet.id)
        #expect(model.note == "ATM 提領現鈔至皮夾")
        #expect(model.hasQuickScenarios)
    }

    @Test("沒有現金時沒有快捷情境")
    func noScenariosWithoutWallet() async {
        let model = await loaded(.sample())

        #expect(!model.hasQuickScenarios)
    }

    @Test("沒選轉出帳戶、沒選轉入帳戶、金額無效，各自有提示，而且不送出")
    func requiredFieldsAreChecked() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let model = await loaded(repository)
        model.amountText = "500"

        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "請選擇轉出帳戶")

        model.fromAccountID = SampleAccounts.savings.id
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "請選擇轉入帳戶")

        model.toAccountID = SampleAccounts.wallet.id
        model.amountText = "0"
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "請輸入大於 0 的金額")
        #expect(await repository.transfers.isEmpty)
    }

    @Test("成功：送出轉出、轉入、金額、台灣時間的今天與備註，回傳後端的訊息，資料版本遞增")
    func submits() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let model = await loaded(repository)
        model.fromAccountID = SampleAccounts.savings.id
        model.toAccountID = SampleAccounts.wallet.id
        model.amountText = "500"
        model.note = "ATM 提款"

        let message = await model.submit()

        #expect(message == "ATM 提款成功 NT$ 500 (iOS 測試存款 ➡️ iOS 測試皮夾)")
        #expect(await repository.transfers == [AccountTransfer(
            fromAccountID: SampleAccounts.savings.id, toAccountID: SampleAccounts.wallet.id,
            amount: Money(500), date: today, note: "ATM 提款"
        )])
        #expect(dataVersion.value == 1)
    }

    @Test("失敗時顯示後端的訊息，資料版本不變")
    func showsRejection() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let model = await loaded(repository)
        model.fromAccountID = SampleAccounts.savings.id
        model.toAccountID = SampleAccounts.wallet.id
        model.amountText = "999999"

        #expect(await model.submit() == nil)

        #expect(model.errorMessage == "轉出帳戶餘額不足（目前餘額：NT$ 50,000）")
        #expect(dataVersion.value == 0)
    }
}
