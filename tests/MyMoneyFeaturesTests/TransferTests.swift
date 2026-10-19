import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("轉帳")
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

    @Test("從現金或活存帳戶的「轉帳」打開:這個帳戶是轉入,轉出是空的(只帶入這一側,上游 ADR 0011)")
    func openedFromAnAccount() async {
        let accounts = AccountsModel(
            repository: InMemoryAccountRepository.sampleWithCash(), dataVersion: dataVersion, defaults: UserDefaults.isolated()
        )
        for account in [Account.cash(SampleAccounts.wallet), .bank(SampleAccounts.savings)] {
            let transfer = accounts.makeTransfer(into: account)
            await transfer.load()
            #expect(transfer.toAccountID == account.id, "\(account.name) 該是轉入")
            #expect(transfer.fromAccountID == nil, "轉出不該預選")
        }
    }

    @Test("開窗時轉出與轉入是同一個帳戶:轉入清成空(上游開窗時的處理)")
    func sameAccountOnOpenClearsTheTarget() async {
        let model = await loaded(from: SampleAccounts.wallet.id, to: SampleAccounts.wallet.id)

        #expect(model.fromAccountID == SampleAccounts.wallet.id)
        #expect(model.toAccountID == nil)
    }

    @Test("選了轉出與轉入之後再載入一次(從帳戶清單頁返回時 .task 會重跑):選擇不會被洗回空值")
    func reloadKeepsTheSelection() async {
        let model = await loaded()
        model.fromAccountID = SampleAccounts.savings.id
        model.toAccountID = SampleAccounts.wallet.id

        await model.load()

        #expect(model.fromAccountID == SampleAccounts.savings.id, "轉出被重設了")
        #expect(model.toAccountID == SampleAccounts.wallet.id, "轉入被重設了")
    }

    @Test("第一次載入失敗:顯示錯誤、沒有預設帶入;重新載入成功後清掉錯誤，這時才帶入預設(從帳戶捷徑進來的那一側)")
    func loadFailureThenRetry() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        await repository.fail(with: .rejected("網路不通"))
        let model = TransferModel(
            repository: repository, dataVersion: dataVersion, today: { today }, preferredFrom: SampleAccounts.savings.id
        )

        await model.load()
        #expect(model.errorMessage == "網路不通")
        #expect(model.candidates.isEmpty)
        #expect(model.fromAccountID == nil, "沒載入成功就不該帶入預設")

        await repository.recover()
        await model.load()

        #expect(model.errorMessage == nil, "重新載入成功後舊的錯誤訊息還在")
        #expect(model.candidates.count == 2)
        #expect(model.fromAccountID == SampleAccounts.savings.id)
    }

    @Test("互換:轉出與轉入對調;轉出是空的時,轉入移到轉出、轉入變空(從帳戶選單進來只帶了轉入)")
    func swapAccounts() async {
        let model = await loaded(to: SampleAccounts.wallet.id)

        model.swapAccounts()
        #expect(model.fromAccountID == SampleAccounts.wallet.id)
        #expect(model.toAccountID == nil)

        model.toAccountID = SampleAccounts.savings.id
        model.swapAccounts()
        #expect(model.fromAccountID == SampleAccounts.savings.id)
        #expect(model.toAccountID == SampleAccounts.wallet.id)
        #expect(model.toCandidates.map(\.name) == ["iOS 測試皮夾"], "互換後轉入的選項仍要排除轉出帳戶")

        model.toAccountID = nil
        model.swapAccounts()
        #expect(model.fromAccountID == nil)
        #expect(model.toAccountID == SampleAccounts.savings.id)
    }

    @Test("互換不動金額、日期、備註")
    func swapKeepsTheRest() async {
        let model = await loaded(to: SampleAccounts.wallet.id)
        model.amountText = "500"
        model.note = "備註"

        model.swapAccounts()

        #expect(model.amountText == "500")
        #expect(model.note == "備註")
        #expect(model.date == today)
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
        #expect(model.errorMessage == "請輸入有效的金額")
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

        #expect(message == "ATM 提款成功 NT$ 500 (iOS 測試存款 -> iOS 測試皮夾)")
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
