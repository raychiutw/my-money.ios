import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("帳戶頁(瀏覽)")
struct AccountsTests {
    @Test("載入後依類型分成銀行存款帳戶與信用卡帳戶兩區，順序跟後端一樣")
    func splitsAccountsByKind() async {
        let model = AccountsModel(repository: InMemoryAccountRepository.sample())

        await model.load()

        #expect(model.bankAccounts.map(\.name) == ["iOS 測試存款"])
        #expect(model.creditCards.map(\.name) == ["iOS 測試信用卡", "iOS 測試小額卡"])
    }

    @Test("三張統計卡：銀行存款帳戶餘額合計、待繳卡費總額、淨可用資產")
    func summaryCards() async {
        let model = AccountsModel(repository: InMemoryAccountRepository.sample())

        await model.load()

        #expect(model.bankBalanceTotal == Money(50000))
        #expect(model.bankAccountCountText == "1 個銀行存款帳戶")
        #expect(model.totalCardDue == Money(28500))
        #expect(model.billedDebtTotal == Money(20000))
        #expect(model.unbilledDebtTotal == Money(8500))
        #expect(model.availableBalance == Money(21500))
    }

    @Test("資料回來之前是載入中，不顯示任何金額", .timeLimit(.minutes(1)))
    func showsLoadingBeforeDataArrives() async {
        let gate = Gate()
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(gate: gate))

        let loading = Task { await model.load() }
        await gate.waitUntilReached()

        #expect(model.phase == .loading)
        #expect(model.availableBalance == nil)
        #expect(model.bankAccounts.isEmpty)

        await gate.open()
        await loading.value
        #expect(model.phase == .loaded)
    }

    @Test("載入失敗時顯示後端的訊息")
    func showsFailure() async {
        let repository = InMemoryAccountRepository.sample()
        await repository.fail(with: .rejected("帳戶不存在"))
        let model = AccountsModel(repository: repository)

        await model.load()

        #expect(model.phase == .failed("帳戶不存在"))
    }

    @Test("重新載入(下拉更新)會拿到最新的資料")
    func reloadFetchesLatestData() async {
        let repository = InMemoryAccountRepository.sample()
        let model = AccountsModel(repository: repository)
        await model.load()

        await repository.replace(accounts: [], summary: .zero)
        await model.load()

        #expect(model.bankAccounts.isEmpty)
        #expect(model.creditCards.isEmpty)
        #expect(model.availableBalance == Money(0))
    }

    @Test("沒有任何資金帳戶時，兩區都是空的")
    func emptyAccounts() async {
        let model = AccountsModel(repository: InMemoryAccountRepository(accounts: [], summary: .zero))

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.bankAccounts.isEmpty)
        #expect(model.creditCards.isEmpty)
        #expect(model.bankAccountCountText == "0 個銀行存款帳戶")
    }
}
