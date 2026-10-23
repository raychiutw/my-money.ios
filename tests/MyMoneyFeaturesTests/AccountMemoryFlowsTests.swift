import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 轉帳與信用卡還款的帳戶記憶(#278):轉出、轉入、扣款帳戶各自記憶,優先序是
/// 捷徑帶入的那一側＞信用卡綁定的預設扣款帳戶＞上次記憶＞空白(`docs/parity.md` 第 93 項)。
@MainActor
@Suite("帳戶記憶:轉帳與信用卡還款")
struct AccountMemoryFlowsTests {
    private let suite = "AccountMemoryFlows-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let me = UserID("me")
    private let dataVersion = DataVersion()
    private let wallet = SampleAccounts.wallet
    private let savings = SampleAccounts.savings

    private func memory(_ purpose: AccountMemory.Purpose) -> AccountMemory {
        AccountMemory(defaults: defaults, userID: me, purpose: purpose)
    }

    private func transfer(from: AccountID? = nil, to: AccountID? = nil) async -> TransferModel {
        let model = TransferModel(
            repository: InMemoryAccountRepository.sampleWithCash(), dataVersion: dataVersion,
            preferredFrom: from, preferredTo: to,
            fromMemory: memory(.transferFrom), toMemory: memory(.transferTo)
        )
        await model.load()
        return model
    }

    @Test("轉帳:送出成功後轉出與轉入各自記住,下次打開帶入")
    func transferRemembersBothSides() async {
        defaults.removePersistentDomain(forName: suite)
        let first = await transfer()
        #expect(first.fromAccountID == nil && first.toAccountID == nil)
        first.fromAccountID = savings.id
        first.toAccountID = wallet.id
        first.amountText = "100"
        #expect(await first.submit() != nil)

        let next = await transfer()
        #expect(next.fromAccountID == savings.id)
        #expect(next.toAccountID == wallet.id)
        #expect(memory(.quickEntry).recall(among: SampleAccounts.all) == nil, "不影響記一筆的記憶")
    }

    @Test("轉帳:捷徑帶入的那一側優先,另一側仍可由記憶帶入;記憶與捷徑同一個帳戶時留捷徑")
    func shortcutWinsOverMemory() async {
        defaults.removePersistentDomain(forName: suite)
        memory(.transferFrom).remember(savings.id)
        memory(.transferTo).remember(wallet.id)

        let shortcut = await transfer(to: savings.id)
        #expect(shortcut.toAccountID == savings.id, "捷徑的轉入優先於記憶")
        #expect(shortcut.fromAccountID == nil, "轉出記憶就是捷徑的帳戶:留給捷徑,轉出清空")
    }

    @Test("轉帳:沒送出不更新記憶")
    func transferCancelDoesNotRemember() async {
        defaults.removePersistentDomain(forName: suite)
        let model = await transfer()
        model.fromAccountID = savings.id
        #expect(memory(.transferFrom).recall(among: SampleAccounts.all) == nil)
    }

    private func card(bound: BankAccount?) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "iOS 暫存卡", colorHex: "#FFD4A0", billedDebt: Money(3000), unbilledDebt: Money(500),
            creditLimit: Money(50000), statementDay: 15, paymentDueDay: 5, sharedDebt: Money(1000), personalDebt: Money(2500),
            ownerID: InMemoryAuthRepository.Member.sample.user.id, isMasked: false,
            paymentAccountID: bound?.id, paymentAccountName: bound?.name
        )
    }

    private func payment(bound: BankAccount? = nil) -> CardPaymentModel {
        CardPaymentModel(
            card: card(bound: bound), preset: .full, bankAccounts: [savings], repository: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion, accountMemory: memory(.cardPaymentBank)
        )
    }

    @Test("信用卡還款:送出成功後記住扣款帳戶,下次帶入;沒綁定也沒記過是空白")
    func paymentRemembers() async {
        defaults.removePersistentDomain(forName: suite)
        let first = payment()
        #expect(first.bankAccountID == nil)
        first.bankAccountID = savings.id
        #expect(await first.submit(confirmedLowBalance: true) == .paid)
        #expect(payment().bankAccountID == savings.id)
    }

    @Test("信用卡還款:卡片綁定的預設扣款帳戶優先於記憶")
    func boundDefaultWinsOverMemory() {
        defaults.removePersistentDomain(forName: suite)
        memory(.cardPaymentBank).remember(AccountID("something-else"))
        let other = BankAccount(id: AccountID("other"), name: "別家", colorHex: "#A8D8EA", balance: Money(10), isJointFund: false)
        let model = CardPaymentModel(
            card: card(bound: other), preset: .full, bankAccounts: [savings, other], repository: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion, accountMemory: memory(.cardPaymentBank)
        )
        #expect(model.bankAccountID == other.id)
    }
}
