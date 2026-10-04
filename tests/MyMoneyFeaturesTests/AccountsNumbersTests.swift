import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("帳戶頁數字優先:組成比例條與卡片的說明(#119)")
struct AccountsNumbersTests {
    private func loaded(_ repository: InMemoryAccountRepository) async -> AccountsModel {
        let model = AccountsModel(repository: repository, dataVersion: DataVersion())
        await model.load()
        return model
    }

    @Test("組成比例條:現金、活存帳戶、信用卡待繳各佔多少(用後端的資金指標)，比例加起來是 100%")
    func compositionFractions() async throws {
        let model = await loaded(.sampleWithCash())

        let segments = model.composition
        #expect(segments.map(\.kind) == [.cash, .bank, .cardDue])
        #expect(segments.map(\.amount) == [Money(1500), Money(50000), Money(28500)])
        // 1,500 + 50,000 + 28,500 = 80,000。
        let fractions = segments.map(\.fraction)
        #expect(abs(fractions[0] - 0.01875) < 0.00001)
        #expect(abs(fractions[1] - 0.625) < 0.00001)
        #expect(abs(fractions[2] - 0.35625) < 0.00001)
        #expect(abs(fractions.reduce(0, +) - 1) < 0.00001)
    }

    @Test("金額是 0 的項目不畫在比例條上")
    func zeroSegmentsAreLeftOut() async {
        let model = await loaded(.sample())

        // 範例沒有現金:現金總額是 0。
        #expect(model.composition.map(\.kind) == [.bank, .cardDue])
    }

    @Test("沒有任何金額，或還沒載入時，沒有比例條")
    func noCompositionWithoutNumbers() async {
        let empty = await loaded(InMemoryAccountRepository(accounts: [], summary: .zero))
        #expect(empty.composition.isEmpty)
        #expect(empty.compositionSummary == nil)

        let notLoaded = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion())
        #expect(notLoaded.composition.isEmpty)
    }

    @Test("活存帳戶透支(餘額合計是負數)時，負數不畫在比例條上")
    func negativeBankBalanceIsLeftOut() async {
        let overdrawn = BalanceSummary(
            cashTotal: Money(1000), bankBalanceTotal: Money(-500), billedDebtTotal: Money(500), unbilledDebtTotal: .zero,
            availableBalance: Money(0), monthlyAmortization: .zero, monthlySavingsReserve: .zero, disposableCash: .zero
        )
        let model = await loaded(InMemoryAccountRepository(accounts: [], summary: overdrawn))

        #expect(model.composition.map(\.kind) == [.cash, .cardDue])
    }

    @Test("VoiceOver 念出每一項的名稱與百分比")
    func compositionSummary() async {
        let model = await loaded(.sampleWithCash())

        #expect(model.compositionSummary == "資金組成，現金百分之 2，活存帳戶百分之 63，信用卡待繳百分之 36")
    }

    @Test("信用卡卡片的說明:歸屬與繳款日;有待繳才有警示色")
    func creditCardCaption() {
        #expect(SampleAccounts.card.cardCaption == "個人私帳・5 日繳")
        let joint = CreditCard(
            id: AccountID("joint"), name: "家庭卡", colorHex: "#FFD4A0", billedDebt: .zero, unbilledDebt: .zero, creditLimit: nil,
            statementDay: nil, paymentDueDay: nil, isJointFund: true
        )
        #expect(joint.cardCaption == "家庭公帳")
        #expect(!joint.isDue)
        #expect(SampleAccounts.card.isDue)
    }
}
