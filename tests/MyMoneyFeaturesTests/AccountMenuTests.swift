import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 帳戶列與詳細頁的 ⋯ 選單:項目由 model 決定，列、詳細頁 toolbar 共用同一份。
@MainActor
@Suite("帳戶 ⋯ 選單")
struct AccountMenuTests {
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let mei = UserID("sample-mei")
    private let dataVersion = DataVersion()

    private func accountsModel(role: HouseholdRole? = .member, accounts: [Account]) async -> AccountsModel {
        let model = AccountsModel(
            repository: InMemoryAccountRepository(accounts: accounts, summary: SampleAccounts.summary), dataVersion: dataVersion,
            permissions: PermissionsModel(userID: me, role: role), defaults: UserDefaults.isolated()
        )
        await model.load()
        return model
    }

    private func bank(_ id: String, owner: UserID, joint: Bool) -> BankAccount {
        BankAccount(id: AccountID(id), name: id, colorHex: "#A8D8EA", balance: Money(100), isJointFund: joint, ownerID: owner)
    }

    private func card(owner: UserID, joint: Bool, billed: Int = 1000, unbilled: Int = 500) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)), unbilledDebt: Money(Decimal(unbilled)),
            creditLimit: nil, statementDay: 15, paymentDueDay: 5, sharedDebt: .zero, personalDebt: Money(Decimal(billed + unbilled)),
            isJointFund: joint, ownerID: owner
        )
    }

    @Test("現金與活存帳戶:轉帳、編輯、刪除(刪除在最後)")
    func cashAndBank() async {
        let mine = Account.bank(bank("mine", owner: me, joint: false))
        let wallet = Account.cash(SampleAccounts.wallet)
        let model = await accountsModel(accounts: [mine, wallet])

        #expect(model.menuItems(for: mine) == [.transfer, .edit, .delete])
        #expect(model.menuItems(for: wallet) == [.transfer, .edit, .delete])
    }

    @Test("沒有修改權限的家庭共同帳戶:只剩轉帳(轉帳照舊)")
    func withoutModifyPermission() async {
        let meiJoint = Account.bank(bank("mei-joint", owner: mei, joint: true))
        let model = await accountsModel(role: .member, accounts: [meiJoint])

        #expect(model.menuItems(for: meiJoint) == [.transfer])
    }

    @Test("信用卡:繳款項目、出帳作業、校準未出帳、編輯、刪除,沒有轉帳;沒有對應欠款的繳款項目隱藏")
    func creditCard() async {
        let mine = Account.creditCard(card(owner: me, joint: false))
        let model = await accountsModel(accounts: [mine])

        #expect(model.menuItems(for: mine) == [.pay(.personal), .pay(.full), .rollover, .reconcile, .edit, .delete])

        let settled = Account.creditCard(card(owner: me, joint: false, billed: 0, unbilled: 0))
        let settledModel = await accountsModel(accounts: [settled])
        #expect(settledModel.menuItems(for: settled) == [.rollover, .reconcile, .edit, .delete], "已結清:沒有繳款")
    }

    @Test("他人的個人卡(脫敏):沒有可做的動作就是空的,畫面不顯示 ⋯")
    func maskedCard() async {
        let others = Account.creditCard(card(owner: mei, joint: false))
        let model = await accountsModel(accounts: [others])

        #expect(model.menuItems(for: others).isEmpty)
    }

    @Test("現金與活存詳細頁的選單跟列上的一樣")
    func detailMenuMatchesRow() async {
        let mine = bank("mine", owner: me, joint: false)
        let accounts = await accountsModel(accounts: [.bank(mine)])
        let detail = accounts.makeAccountDetail(for: .bank(mine))

        #expect(detail.menuItems == accounts.menuItems(for: .bank(mine)))
    }
}

@MainActor
@Suite("現金與活存帳戶詳細頁")
struct AccountDetailTests {
    private let dataVersion = DataVersion()

    private func detail(
        _ account: Account, repository: InMemoryAccountRepository = .sampleWithCash()
    ) async -> (AccountDetailModel, AccountsModel) {
        let accounts = AccountsModel(repository: repository, dataVersion: dataVersion, defaults: UserDefaults.isolated())
        await accounts.load()
        return (accounts.makeAccountDetail(for: account), accounts)
    }

    @Test("現金:現金餘額與歸屬;活存:餘額與歸屬")
    func rows() async {
        let (cash, _) = await detail(.cash(SampleAccounts.wallet))
        #expect(cash.rows.map(\.title) == ["現金餘額", "歸屬"])
        #expect(cash.rows.first?.value == SampleAccounts.wallet.balance.formatted())
        #expect(cash.rows.last?.value == "個人私帳")

        let (bank, _) = await detail(.bank(SampleAccounts.savings))
        #expect(bank.rows.map(\.title) == ["餘額", "歸屬"])
    }

    @Test("活存帳戶有信用卡綁定它時,詳細頁有待扣卡費預覽,數字跟帳戶頁一樣")
    func debitPreview() async {
        let repository = InMemoryAccountRepository(
            accounts: [.bank(SampleAccounts.savings), .creditCard(SampleAccounts.cardBoundToSavings)], summary: SampleAccounts.summary
        )
        let (bank, accounts) = await detail(.bank(SampleAccounts.savings), repository: repository)

        #expect(bank.debitPreview != nil)
        #expect(bank.debitPreview == accounts.debitPreview(for: SampleAccounts.savings))

        let (cash, _) = await detail(.cash(SampleAccounts.wallet))
        #expect(cash.debitPreview == nil)
    }

    @Test("轉帳:這個帳戶是轉入,轉出空白")
    func transferIntoThisAccount() async {
        let (detail, _) = await detail(.cash(SampleAccounts.wallet))
        let transfer = detail.makeTransfer()
        await transfer.load()

        #expect(transfer.toAccountID == SampleAccounts.wallet.id)
        #expect(transfer.fromAccountID == nil)
    }

    @Test("資料版本改變後重新取得最新的帳戶;帳戶被刪除就 isGone")
    func refreshAndGone() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let (detail, _) = await detail(.cash(SampleAccounts.wallet), repository: repository)

        try? await repository.delete(SampleAccounts.wallet.id)
        dataVersion.bump()
        await detail.refreshIfStale()

        #expect(detail.isGone)
    }

    @Test("從詳細頁刪除:成功後資料版本遞增;失敗顯示訊息、版本不變")
    func delete() async {
        let repository = InMemoryAccountRepository.sampleWithCash()
        let (detail, _) = await detail(.cash(SampleAccounts.wallet), repository: repository)
        let before = dataVersion.value

        await repository.fail(with: .rejected("無法刪除"))
        await detail.delete()
        #expect(detail.alertMessage == "無法刪除")
        #expect(dataVersion.value == before)

        await repository.recover()
        await detail.delete()
        #expect(dataVersion.value == before + 1)
    }
}
