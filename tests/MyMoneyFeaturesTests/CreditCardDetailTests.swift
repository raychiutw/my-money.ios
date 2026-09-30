import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("信用卡精簡列")
struct CreditCardSummaryRowTests {
    @Test("第 2 行只放一項：有待繳時是繳款日，信用卡待繳總額是 0 時是「已全數結清」;有待繳但沒有繳款日時沒有第 2 行")
    func summaryLine() {
        #expect(SampleAccounts.card.summaryLine == "每月 5 日繳款")
        #expect(SampleAccounts.lowLimitCard.summaryLine == "每月 20 日繳款")

        let settled = CreditCard(
            id: AccountID("settled"), name: "卡", colorHex: "#FFD4A0", billedDebt: .zero, unbilledDebt: .zero,
            creditLimit: nil, statementDay: 15, paymentDueDay: 5
        )
        #expect(settled.summaryLine == "已全數結清")

        let withoutDueDay = CreditCard(
            id: AccountID("no-due-day"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(100), unbilledDebt: .zero,
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )
        #expect(withoutDueDay.summaryLine == nil)
    }
}

@MainActor
@Suite("信用卡詳細頁")
struct CreditCardDetailTests {
    private let dataVersion = DataVersion()
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func card(billed: Int, unbilled: Int, shared: Int, personal: Int) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)),
            unbilledDebt: Money(Decimal(unbilled)), creditLimit: nil, statementDay: 15, paymentDueDay: 5,
            sharedDebt: Money(Decimal(shared)), personalDebt: Money(Decimal(personal))
        )
    }

    private func detail(
        _ card: CreditCard,
        scope: AccountScope = .all,
        repository: InMemoryAccountRepository = InMemoryAccountRepository.sample()
    ) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: [SampleAccounts.savings], loadedVersion: dataVersion.value, scope: scope, repository: repository,
            dataVersion: dataVersion, today: { today }
        )
    }

    @Test("「繳款」選單只列有對應欠款的項目：家庭代墊公帳、個人私帳消費、信用卡待繳總額是 0 的項目隱藏")
    func paymentPresets() {
        #expect(detail(SampleAccounts.card).paymentPresets == [.shared, .personal, .full])
        // 小額卡沒有欠款公私拆解，只能全額結清。
        #expect(detail(SampleAccounts.lowLimitCard).paymentPresets == [.full])
        #expect(detail(card(billed: 500, unbilled: 0, shared: 500, personal: 0)).paymentPresets == [.shared, .full])
        #expect(detail(card(billed: 0, unbilled: 800, shared: 0, personal: 800)).paymentPresets == [.personal, .full])
        #expect(detail(card(billed: 0, unbilled: 0, shared: 0, personal: 0)).paymentPresets.isEmpty)
    }

    @Test("有未出帳款才顯示「出帳作業」,不看結帳日(web 在 82d9124 拿掉了結帳日的條件)")
    func showsRolloverOnlyWithUnbilled() {
        #expect(detail(SampleAccounts.card).showsRollover)
        #expect(detail(card(billed: 0, unbilled: 1, shared: 0, personal: 1)).showsRollover)
        #expect(!detail(card(billed: 5000, unbilled: 0, shared: 0, personal: 5000)).showsRollover)
    }

    @Test("出帳作業的確認說明轉入本期已出帳待繳款(#56);確認後做出帳作業，顯示後端的訊息，資料版本遞增")
    func rollOver() async {
        let repository = InMemoryAccountRepository.sample()
        let model = detail(SampleAccounts.lowLimitCard, repository: repository)

        #expect(model.rolloverConfirmation == "確定要將「iOS 測試小額卡」的未出帳款 $5,000 轉入本期已出帳待繳款嗎？")
        await model.rollOver()

        #expect(await repository.rolledOverIDs == [SampleAccounts.lowLimitCard.id])
        // 後端的原文(疊字已回報 onion523/my-money#27),照原樣顯示。
        #expect(model.noticeMessage == "已將未出帳 NT$ 5,000 成功出帳作業為已出帳待繳款！")
        #expect(dataVersion.value == 1)
    }

    @Test("出帳作業失敗時顯示後端的錯誤，資料版本不變")
    func rollOverFailure() async {
        let repository = InMemoryAccountRepository.sample()
        await repository.fail(with: .rejected("目前無未出帳金額需出帳作業"))
        let model = detail(SampleAccounts.lowLimitCard, repository: repository)

        await model.rollOver()

        #expect(model.alertMessage == "目前無未出帳金額需出帳作業")
        #expect(model.noticeMessage == nil)
        #expect(dataVersion.value == 0)
    }

    @Test("從「繳款」選單繳家庭代墊：扣款帳戶是這個範圍的銀行存款帳戶;成功後資料版本遞增，詳細頁重新取得這張卡和扣款帳戶")
    func refreshesAfterPayment() async {
        let repository = InMemoryAccountRepository.sample()
        let model = detail(SampleAccounts.card, scope: .personal, repository: repository)

        let payment = model.makePayment(.shared)
        #expect(payment.amountText == "3000")
        #expect(payment.bankAccounts.map(\.id) == [SampleAccounts.savings.id])
        #expect(await payment.submit() == .paid)
        await model.refreshIfStale()

        #expect(model.card.billedDebt == Money(9000))
        #expect(model.bankAccounts.map(\.balance) == [Money(47000)])
        // 跟打開詳細頁的畫面同一個帳戶檢視範圍。
        #expect(await repository.requestedScopes == [.personal])
    }

    @Test("出帳作業之後重新取得：未出帳款轉入已出帳待繳款，不再顯示出帳作業")
    func refreshesAfterRollover() async {
        let repository = InMemoryAccountRepository.sample()
        let model = detail(SampleAccounts.lowLimitCard, repository: repository)

        await model.rollOver()
        await model.refreshIfStale()

        #expect(model.card.billedDebt == Money(13000))
        #expect(model.card.unbilledDebt == .zero)
        #expect(!model.showsRollover)
    }

    /// 例如在總覽記了一筆信用卡支出，帳戶頁還沒重新載入完就點進信用卡(code review)。
    @Test("帳戶頁的資料比目前的資料版本舊時，打開的詳細頁會重新取得")
    func refreshesWhenOpenedFromStaleAccounts() async {
        let repository = InMemoryAccountRepository.sample()
        let accounts = AccountsModel(repository: repository, dataVersion: dataVersion)
        await accounts.load()
        dataVersion.bump()
        let fetchesBefore = await repository.fetchCount

        let model = accounts.makeCardDetail(for: SampleAccounts.card)
        await model.refreshIfStale()

        #expect(await repository.fetchCount == fetchesBefore + 1)
    }

    @Test("資料版本沒變時不重新取得(剛打開時用精簡列的資料)")
    func doesNotRefetchWhenFresh() async {
        let repository = InMemoryAccountRepository.sample()
        let model = detail(SampleAccounts.card, repository: repository)

        await model.refreshIfStale()

        #expect(await repository.fetchCount == 0)
        #expect(model.card == SampleAccounts.card)
    }

    @Test("重新取得時這張卡已經不在這個帳戶檢視範圍(被刪除，或歸屬改了),就要回到上一頁")
    func goneWhenCardDisappears() async throws {
        let repository = InMemoryAccountRepository.sample()
        let model = detail(SampleAccounts.card, repository: repository)
        #expect(!model.isGone)

        try await repository.delete(SampleAccounts.card.id)
        dataVersion.bump()
        await model.refreshIfStale()

        #expect(model.isGone)
    }

    @Test("toolbar 的「編輯」打開這張卡的資產帳戶編輯器")
    func editorEditsThisCard() {
        let editor = detail(SampleAccounts.card).makeEditor()

        #expect(editor.kind == .creditCard)
        #expect(editor.name == "iOS 測試信用卡")
        #expect(!editor.canChangeKind)
    }
}
