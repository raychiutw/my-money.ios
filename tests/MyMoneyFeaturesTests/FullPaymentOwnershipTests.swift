import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 「全額結清」的預設歸屬與換扣款帳戶時的連動(上游 `b3e0c92`、ADR 0037 決策 3,#330)。
@MainActor
@Suite("全額結清的預設歸屬")
struct FullPaymentOwnershipTests {
    private let dataVersion = DataVersion()
    private let savings = SampleAccounts.savings
    private let jointFund = BankAccount(
        id: AccountID("joint-fund"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true
    )

    private func card(
        shared: Decimal, personal: Decimal, bound: BankAccount? = nil, isJointFund: Bool = false, masked: Bool = false
    ) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "iOS 暫存卡", colorHex: "#FFD4A0", billedDebt: Money(shared + personal), unbilledDebt: .zero,
            creditLimit: masked ? nil : Money(50000), statementDay: 15, paymentDueDay: 5, sharedDebt: Money(shared), personalDebt: Money(personal),
            isJointFund: isJointFund, ownerID: masked ? UserID("sample-mei") : InMemoryAuthRepository.Member.sample.user.id, isMasked: masked,
            paymentAccountID: bound?.id, paymentAccountName: bound?.name
        )
    }

    private func payment(
        _ card: CreditCard, preset: CardPaymentModel.Preset = .full, isMaskedCard: Bool = false, memory: AccountMemory? = nil
    ) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: [savings, jointFund], repository: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion, isMaskedCard: isMaskedCard, accountMemory: memory,
            today: { CalendarDay(year: 2026, month: 11, day: 14) }
        )
    }

    @Test("只有個人私帳欠款:預設個人私帳,即使帶入的是家庭共同帳戶")
    func onlyPersonalDebtDefaultsToPersonal() {
        #expect(payment(card(shared: 0, personal: 2500, bound: jointFund)).isShared == false)
    }

    @Test("帶入的扣款帳戶決定歸屬:家庭共同帳戶 → 家庭公帳,個人活存帳戶 → 個人私帳")
    func prefilledBankDecides() {
        #expect(payment(card(shared: 1000, personal: 2500, bound: jointFund)).isShared == true)
        #expect(payment(card(shared: 1000, personal: 2500, bound: savings, isJointFund: true)).isShared == false)
    }

    @Test("沒帶入扣款帳戶、只有公帳欠款:家庭公帳")
    func onlySharedDebtDefaultsToShared() {
        #expect(payment(card(shared: 1000, personal: 0)).isShared == true)
    }

    @Test("沒帶入扣款帳戶、公私都有欠款:依卡片本身是不是家庭共同帳戶")
    func fallsBackToCardOwnership() {
        #expect(payment(card(shared: 1000, personal: 2500)).isShared == false)
        #expect(payment(card(shared: 1000, personal: 2500, isJointFund: true)).isShared == true)
    }

    @Test("換扣款帳戶:歸屬跟著新帳戶的公私性質")
    func changingBankFollowsItsOwnership() {
        let model = payment(card(shared: 1000, personal: 2500))

        model.bankAccountID = jointFund.id
        #expect(model.isShared == true)
        model.bankAccountID = savings.id
        #expect(model.isShared == false)
    }

    @Test("只有私帳欠款:換成家庭共同帳戶也維持個人私帳")
    func onlyPersonalDebtDoesNotFollowBank() {
        let model = payment(card(shared: 0, personal: 2500))

        model.bankAccountID = jointFund.id

        #expect(model.isShared == false)
    }

    @Test("手動選過歸屬之後,換扣款帳戶不再改動它")
    func manualChoiceLocksOwnership() {
        let model = payment(card(shared: 1000, personal: 2500, bound: jointFund))

        model.isShared = false
        model.bankAccountID = AccountID("joint-fund")
        model.bankAccountID = savings.id
        model.bankAccountID = jointFund.id

        #expect(model.isShared == false)
    }

    @Test("改備註不影響連動(與 web 用備註結尾判斷不同,上游 #191)")
    func editingNoteKeepsLinkage() {
        let model = payment(card(shared: 1000, personal: 2500))

        model.note += " 十一月"
        model.bankAccountID = jointFund.id

        #expect(model.isShared == true)
    }

    @Test("繳家庭代墊、繳個人私帳:預設歸屬不變,換扣款帳戶也不連動", arguments: [
        (CardPaymentModel.Preset.shared, true), (.personal, false),
    ])
    func otherPresetsUnchanged(preset: CardPaymentModel.Preset, expected: Bool) {
        let model = payment(card(shared: 1000, personal: 2500, bound: savings), preset: preset)
        #expect(model.isShared == expected)

        model.bankAccountID = expected ? savings.id : jointFund.id

        #expect(model.isShared == expected)
    }

    @Test("帶入的是上次繳款用的扣款帳戶(#278)時,同樣由它決定歸屬")
    func rememberedBankDecides() {
        let memory = AccountMemory(
            defaults: UserDefaults(suiteName: "FullPaymentOwnership-\(UUID().uuidString)")!,
            userID: InMemoryAuthRepository.Member.sample.user.id, purpose: .cardPaymentBank
        )
        memory.remember(jointFund.id)

        let model = payment(card(shared: 1000, personal: 2500), memory: memory)

        #expect(model.bankAccountID == jointFund.id)
        #expect(model.isShared == true)
    }

    @Test("他人私卡從「全額結清」打開:仍只繳家庭代墊、家庭公帳,換扣款帳戶也不連動")
    func maskedCardStaysShared() {
        let model = payment(card(shared: 1000, personal: 0, masked: true), isMaskedCard: true)
        #expect(model.isShared == true)

        model.bankAccountID = savings.id

        #expect(model.isShared == true)
    }
}
