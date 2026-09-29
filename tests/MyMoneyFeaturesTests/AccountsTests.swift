import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("帳戶頁(瀏覽)")
struct AccountsTests {
    @Test("帳戶選單標示正確的類型(web 的週期收支把現金錢包標成「信用卡」);轉帳和撥款報銷的選單另外帶餘額")
    func menuTitlesShowAccountKind() {
        #expect(Account.cash(SampleAccounts.wallet).menuTitle == "iOS 測試皮夾(現金錢包)")
        #expect(Account.bank(SampleAccounts.savings).menuTitle == "iOS 測試存款(銀行存款帳戶)")
        #expect(Account.creditCard(SampleAccounts.card).menuTitle == "iOS 測試信用卡(信用卡)")
        #expect(Account.cash(SampleAccounts.wallet).menuTitleWithBalance == "iOS 測試皮夾(現金錢包，餘額 $1,500)")
        #expect(Account.bank(SampleAccounts.savings).menuTitleWithBalance == "iOS 測試存款(銀行存款帳戶，餘額 $50,000)")
        #expect(ReceivingAccount(id: AccountID("mei-bank"), name: "小美薪轉", kind: .bank).menuTitle == "小美薪轉(銀行存款帳戶)")
    }

    @Test("載入後依類型分成銀行存款帳戶與信用卡帳戶兩區，順序跟後端一樣")
    func splitsAccountsByKind() async {
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion())

        await model.load()

        #expect(model.bankAccounts.map(\.name) == ["iOS 測試存款"])
        #expect(model.creditCards.map(\.name) == ["iOS 測試信用卡", "iOS 測試小額卡"])
    }

    @Test("三張統計卡：銀行存款帳戶餘額合計、信用卡待繳總額、淨可用餘額")
    func summaryCards() async {
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion())

        await model.load()

        #expect(model.bankBalanceTotal == Money(50000))
        #expect(model.bankAccountCountText == "1 個銀行存款帳戶")
        #expect(model.totalCardDue == Money(28500))
        #expect(model.billedDebtTotal == Money(20000))
        #expect(model.unbilledDebtTotal == Money(8500))
        #expect(model.availableBalance == Money(21500))
    }

    @Test("現金錢包自成一區，統計卡多一張現金錢包總額;淨可用餘額照後端(含現金)")
    func cashWalletsAreTheirOwnSection() async {
        let model = AccountsModel(repository: InMemoryAccountRepository.sampleWithCash(), dataVersion: DataVersion())

        await model.load()

        #expect(model.cashWallets.map(\.name) == ["iOS 測試皮夾"])
        #expect(model.bankAccounts.map(\.name) == ["iOS 測試存款"])
        #expect(model.cashTotal == Money(1500))
        #expect(model.cashWalletCountText == "1 個現金錢包")
        #expect(model.availableBalance == Money(23000))
    }

    @Test("帳戶檢視範圍預設全部;切到家庭共同基金時，帳戶和資金指標都照這個範圍重新取得")
    func scopeAppliesToAccountsAndSummary() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let model = AccountsModel(repository: repository, dataVersion: DataVersion())
        #expect(model.scope == .all)
        await model.load()

        model.scope = .household
        await model.load()

        #expect(await repository.requestedScopes == [.all, .household])
        #expect(await repository.requestedSummaryScopes == [.all, .household])
        #expect(model.cashWallets.isEmpty && model.bankAccounts.isEmpty && model.creditCards.isEmpty)
    }

    @Test("切換帳戶檢視範圍重新載入期間，維持已載入的內容，不回到骨架屏(web 的二度篩選過渡)", .timeLimit(.minutes(1)))
    func reloadKeepsLoadedContent() async {
        let gate = Gate()
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(gate: gate), dataVersion: DataVersion())
        await gate.open()
        await model.load()

        await gate.close()
        model.scope = .household
        let reloading = Task { await model.load() }
        await gate.waitUntilReached()
        #expect(model.phase == .loaded)
        #expect(model.bankAccounts.map(\.name) == ["iOS 測試存款"])
        await gate.open()
        await reloading.value
    }

    @Test("換了檢視範圍之後，就算資料版本沒變也要重抓(畫面用範圍和資料版本當 task 的 key)")
    func changingScopeMakesDataStale() async {
        let repository = InMemoryAccountRepository.sample()
        let model = AccountsModel(repository: repository, dataVersion: DataVersion())
        await model.refreshIfStale()
        await model.refreshIfStale()
        #expect(await repository.requestedScopes == [.all])

        model.scope = .personal
        await model.refreshIfStale()

        #expect(await repository.requestedScopes == [.all, .personal])
    }

    @Test("資料回來之前是載入中，不顯示任何金額", .timeLimit(.minutes(1)))
    func showsLoadingBeforeDataArrives() async {
        let gate = Gate()
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(gate: gate), dataVersion: DataVersion())

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
        let model = AccountsModel(repository: repository, dataVersion: DataVersion())

        await model.load()

        #expect(model.phase == .failed("帳戶不存在"))
    }

    @Test("重新載入(下拉更新)會拿到最新的資料")
    func reloadFetchesLatestData() async {
        let repository = InMemoryAccountRepository.sample()
        let model = AccountsModel(repository: repository, dataVersion: DataVersion())
        await model.load()

        await repository.replace(accounts: [], summary: .zero)
        await model.load()

        #expect(model.bankAccounts.isEmpty)
        #expect(model.creditCards.isEmpty)
        #expect(model.availableBalance == Money(0))
    }

    @Test("沒有任何資產帳戶時，兩區都是空的")
    func emptyAccounts() async {
        let model = AccountsModel(repository: InMemoryAccountRepository(accounts: [], summary: .zero), dataVersion: DataVersion())

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.bankAccounts.isEmpty)
        #expect(model.creditCards.isEmpty)
        #expect(model.bankAccountCountText == "0 個銀行存款帳戶")
    }
    @Test("刪除資產帳戶後資料版本遞增")
    func deletingBumpsDataVersion() async {
        let repository = InMemoryAccountRepository.sample()
        let dataVersion = DataVersion()
        let model = AccountsModel(repository: repository, dataVersion: dataVersion)
        await model.load()

        await model.delete(.creditCard(SampleAccounts.lowLimitCard))

        #expect(await repository.deletedIDs == [SampleAccounts.lowLimitCard.id])
        #expect(dataVersion.value == 1)
        #expect(model.alertMessage == nil)
    }

    @Test("刪除失敗時顯示後端的訊息，資料版本不變")
    func deleteFailureShowsAlert() async {
        let repository = InMemoryAccountRepository.sample()
        let dataVersion = DataVersion()
        let model = AccountsModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        await repository.fail(with: .rejected("帳戶不存在"))

        await model.delete(.bank(SampleAccounts.savings))

        #expect(model.alertMessage == "帳戶不存在")
        #expect(dataVersion.value == 0)
    }

    @Test("刪除前的確認文字提醒交易紀錄會一併刪除")
    func deleteConfirmationMessage() {
        let model = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion())

        #expect(model.deleteConfirmation(for: .bank(SampleAccounts.savings))
            == "確定要刪除帳戶「iOS 測試存款」嗎？這個帳戶的交易紀錄也會一併刪除！")
    }

    @Test("資料版本改變後重新抓資料;沒變時不重抓")
    func refreshesOnlyWhenDataVersionChanges() async {
        let repository = InMemoryAccountRepository.sample()
        let dataVersion = DataVersion()
        let model = AccountsModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        let fetchesAfterFirstLoad = await repository.fetchCount

        await model.refreshIfStale()
        #expect(await repository.fetchCount == fetchesAfterFirstLoad)

        await repository.replace(accounts: [], summary: .zero)
        dataVersion.bump()
        await model.refreshIfStale()

        #expect(await repository.fetchCount > fetchesAfterFirstLoad)
        #expect(model.bankAccounts.isEmpty)
    }
}
