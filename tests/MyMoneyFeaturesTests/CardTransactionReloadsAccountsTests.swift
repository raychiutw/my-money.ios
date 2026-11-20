import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 編輯或刪除已出帳的信用卡收支後,後端同步重算已出帳待繳款與未出帳款(上游 `e9b5df0`、ADR 0045,#368):
/// iOS 不自己算,只要帳戶頁與信用卡詳細頁重新載入,就看得到後端重算的值。重新載入靠共用的資料版本(`reloadKey`)。
@MainActor
@Suite("編刪信用卡收支後重新載入帳戶(#368)")
struct CardTransactionReloadsAccountsTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let dataVersion = DataVersion()

    private var context: SessionContext {
        SessionContext(dataVersion: dataVersion, defaults: UserDefaults.isolated(), today: { today })
    }

    /// 範例信用卡上的一筆消費(耳機)。
    private var headphones: Transaction {
        SampleTransactions.make(today: today).first { $0.note == "耳機" }!
    }

    private func accountScreens() -> (accounts: AccountsModel, card: CreditCardDetailModel) {
        let repository = InMemoryAccountRepository.sample()
        return (
            AccountsModel(repository: repository, context: context),
            CreditCardDetailModel(
                card: SampleAccounts.card, bankAccounts: [], loadedVersion: nil, scope: .all, repository: repository, context: context
            )
        )
    }

    @Test("編輯信用卡收支儲存後:帳戶頁與信用卡詳細頁的重載鍵改變")
    func editingCardTransactionReloadsAccounts() async {
        #expect(headphones.accountID == SampleAccounts.card.id)
        let screens = accountScreens()
        let accountsKey = screens.accounts.reloadKey, cardKey = screens.card.reloadKey
        let editor = TransactionEditorModel(
            editing: headphones, transactions: InMemoryTransactionRepository(transactions: [headphones]),
            accounts: InMemoryAccountRepository.sample(), dataVersion: dataVersion
        )
        await editor.prepare()
        editor.amountText = "990"

        #expect(await editor.save())

        #expect(screens.accounts.reloadKey != accountsKey)
        #expect(screens.card.reloadKey != cardKey)
    }

    @Test("刪除信用卡收支後:帳戶頁與信用卡詳細頁的重載鍵改變")
    func deletingCardTransactionReloadsAccounts() async {
        let screens = accountScreens()
        let accountsKey = screens.accounts.reloadKey, cardKey = screens.card.reloadKey
        let repository = InMemoryTransactionRepository(transactions: [headphones])
        let transactions = TransactionsModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(),
            currentUser: InMemoryAuthRepository.Member.sample.user.id, context: context
        )

        await transactions.delete(headphones)

        #expect(await repository.deletedIDs == [headphones.id])
        #expect(screens.accounts.reloadKey != accountsKey)
        #expect(screens.card.reloadKey != cardKey)
    }
}
