import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 繳款畫面預設帶入信用卡綁定的預設扣款帳戶(上游 `3d09060`)。這是「顯式帳戶選取」(ADR 0011、#112)的明確例外:
/// 預設扣款帳戶是使用者自己設定的,帶入它不算擅自預選。
@MainActor
@Suite("繳款預設帶入預設扣款帳戶")
struct PaymentAccountPrefillTests {
    private let dataVersion = DataVersion()
    private let savings = SampleAccounts.savings
    private let jointFund = BankAccount(
        id: AccountID("joint-fund"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true
    )

    private func card(bound: BankAccount?, masked: Bool = false) -> CreditCard {
        CreditCard(
            id: AccountID("card"), name: "iOS 暫存卡", colorHex: "#FFD4A0", billedDebt: Money(3000), unbilledDebt: Money(500),
            creditLimit: masked ? nil : Money(50000), statementDay: 15, paymentDueDay: 5, sharedDebt: Money(1000), personalDebt: Money(2500),
            ownerID: masked ? UserID("sample-mei") : InMemoryAuthRepository.Member.sample.user.id, isMasked: masked,
            paymentAccountID: bound?.id, paymentAccountName: bound?.name
        )
    }

    private func payment(
        _ card: CreditCard, banks: [BankAccount]? = nil, preset: CardPaymentModel.Preset = .full
    ) -> CardPaymentModel {
        CreditCardDetailModel(
            card: card, bankAccounts: banks ?? [savings, jointFund], loadedVersion: dataVersion.value, scope: .all,
            repository: InMemoryAccountRepository.sample(), dataVersion: dataVersion, today: { CalendarDay(year: 2026, month: 10, day: 18) }
        ).makePayment(preset)
    }

    @Test("三個繳款項目打開,扣款帳戶都已帶入綁定的活存帳戶", arguments: [
        CardPaymentModel.Preset.shared, .personal, .full,
    ])
    func prefillsForEveryPreset(preset: CardPaymentModel.Preset) {
        let model = payment(card(bound: savings), preset: preset)

        #expect(model.bankAccountID == savings.id)
        #expect(model.availableBalance == savings.balance, "帶入後可用餘額那一列跟著出現")
    }

    @Test("帶入之後仍可改選別的扣款帳戶")
    func canBeChanged() {
        let model = payment(card(bound: savings))

        model.bankAccountID = jointFund.id

        #expect(model.bankAccountID == jointFund.id)
    }

    @Test("沒綁定:扣款帳戶維持空白，請使用者自己選(ADR 0011、#112)")
    func unboundStaysEmpty() {
        #expect(payment(card(bound: nil)).bankAccountID == nil)
    }

    @Test("綁定的活存帳戶不在這次可選的清單裡(帳戶範圍不含它、或已被刪除):維持空白,不帶入一個看不到的帳戶")
    func boundButNotAvailableStaysEmpty() {
        #expect(payment(card(bound: savings), banks: [jointFund]).bankAccountID == nil)
        #expect(payment(card(bound: savings), banks: []).bankAccountID == nil)
    }

    @Test("替他人私卡繳家庭代墊(脫敏):不帶入對方綁定的帳戶(那是對方的私人設定)")
    func maskedCardIsNeverPrefilled() {
        let model = payment(card(bound: savings, masked: true), preset: .shared)

        #expect(model.bankAccountID == nil)
    }
}
