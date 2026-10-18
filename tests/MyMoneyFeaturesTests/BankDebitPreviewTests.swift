import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 活存帳戶的待扣卡費預覽(上游 `3d09060`):綁在這個活存帳戶的信用卡,已出帳與總待繳的合計,以及扣掉之後的餘額。
/// 是 web 在前端做的簡單加減(後端沒有彙總端點),全部用後端給的卡片數字。
@MainActor
@Suite("活存帳戶的待扣卡費預覽")
struct BankDebitPreviewTests {
    private func bank(_ id: String = "bank", balance: Int = 5000) -> BankAccount {
        BankAccount(id: AccountID(id), name: "iOS 測試存款", colorHex: "#A8D8EA", balance: Money(Decimal(balance)), isJointFund: false)
    }

    private func card(
        _ id: String, billed: Int, unbilled: Int = 0, bound: String? = "bank", masked: Bool = false
    ) -> CreditCard {
        CreditCard(
            id: AccountID(id), name: id, colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)), unbilledDebt: Money(Decimal(unbilled)),
            creditLimit: nil, statementDay: 15, paymentDueDay: 5, isMasked: masked,
            paymentAccountID: bound.map(AccountID.init), paymentAccountName: bound.map { _ in "iOS 測試存款" }
        )
    }

    @Test("彙總綁在這個活存帳戶的卡:張數、已出帳合計、含未出帳的總待繳、扣已出帳後與扣總待繳後的餘額")
    func totals() throws {
        let preview = try #require(BankDebitPreview.make(
            for: bank(balance: 5000), cards: [card("a", billed: 3000, unbilled: 500), card("b", billed: 1000), card("c", billed: 9999, bound: nil)]
        ))

        #expect(preview.cardCount == 2, "沒綁定的不算")
        #expect(preview.billed == Money(4000))
        #expect(preview.total == Money(4500))
        #expect(preview.balanceAfterBilled == Money(1000))
        #expect(!preview.isShortOfBilled)
        #expect(preview.summaryText == "待扣卡費 2 張・已出帳 $4,000・含未出帳 $4,500")
        #expect(preview.balanceText == "扣已出帳後餘額 $1,000")
        #expect(preview.warningText == nil)
    }

    @Test("沒有任何卡綁在這個活存帳戶:沒有預覽(帳戶列維持原樣)")
    func noBoundCards() {
        #expect(BankDebitPreview.make(for: bank(), cards: [card("a", billed: 100, bound: nil), card("b", billed: 100, bound: "other-bank")]) == nil)
        #expect(BankDebitPreview.make(for: bank(), cards: []) == nil)
    }

    @Test("存款不足扣已出帳:標示不足與差額,VoiceOver 念出「存款不足」")
    func shortOfBilled() throws {
        let preview = try #require(BankDebitPreview.make(for: bank(balance: 3000), cards: [card("a", billed: 4000, unbilled: 200)]))

        #expect(preview.isShortOfBilled)
        #expect(preview.shortfall == Money(1000))
        #expect(preview.balanceAfterBilled == Money(-1000))
        #expect(preview.warningText == "存款不足扣繳已出帳，差 $1,000")
        #expect(preview.spokenText.contains("存款不足扣繳已出帳"))
        #expect(preview.spokenText.contains("待扣卡費 1 張"))
    }

    @Test("剛好夠扣已出帳(餘額 0)不算不足;只有總待繳不夠不警示")
    func exactlyEnoughIsNotShort() throws {
        let exact = try #require(BankDebitPreview.make(for: bank(balance: 4000), cards: [card("a", billed: 4000)]))
        #expect(!exact.isShortOfBilled)
        #expect(exact.warningText == nil)

        let onlyTotalShort = try #require(BankDebitPreview.make(for: bank(balance: 4000), cards: [card("a", billed: 3000, unbilled: 2000)]))
        #expect(onlyTotalShort.total == Money(5000))
        #expect(!onlyTotalShort.isShortOfBilled, "只有含未出帳的總待繳不夠:不警示(未出帳還沒到扣款日)")
    }

    // MARK: 帳戶頁

    @Test("帳戶頁:AccountsModel 依目前載入的卡彙總每個活存帳戶的預覽;沒綁定的活存帳戶沒有")
    func accountsModelPreviews() async throws {
        let savings = bank("bank", balance: 5000)
        let repository = InMemoryAccountRepository(
            accounts: [.bank(savings), .creditCard(card("a", billed: 3000, unbilled: 500))], summary: SampleAccounts.summary
        )
        let model = AccountsModel(repository: repository, dataVersion: DataVersion(), defaults: UserDefaults.isolated())
        await model.load()

        let preview = try #require(model.debitPreview(for: savings))
        #expect(preview.billed == Money(3000))
        #expect(model.debitPreview(for: bank("elsewhere")) == nil)
    }

    @Test("帳戶頁:切到看不到那張卡的範圍時不計入(只算目前範圍載入的卡)")
    func onlyCardsInTheLoadedScopeCount() async throws {
        let savings = bank("bank", balance: 5000)
        let repository = InMemoryAccountRepository(
            accounts: [.bank(savings), .creditCard(card("masked", billed: 900, masked: true))], summary: SampleAccounts.summary
        )
        let model = AccountsModel(repository: repository, dataVersion: DataVersion(), defaults: UserDefaults.isolated())
        model.scope = .household
        await model.load()

        #expect(model.debitPreview(for: savings) == nil, "脫敏卡不計入")
    }
}
