import Foundation
import MyMoneyDomain
import Testing

@Suite("信用卡帳戶的待繳卡費總額與剩餘額度")
struct CreditCardTests {
    private func card(billed: Decimal, unbilled: Decimal, limit: Decimal?) -> CreditCard {
        CreditCard(
            id: AccountID("card"),
            name: "測試卡",
            colorHex: "#FFD4A0",
            billedDebt: Money(billed),
            unbilledDebt: Money(unbilled),
            creditLimit: limit.map(Money.init),
            statementDay: 15,
            paymentDueDay: 5
        )
    }

    @Test("待繳卡費總額是已出帳待繳金額加上未出帳金額")
    func totalDueIsBilledPlusUnbilled() {
        #expect(card(billed: 12000, unbilled: 3500, limit: 100_000).totalDue == Money(15500))
    }

    @Test("剩餘額度是信用額度扣掉待繳卡費總額")
    func remainingCreditIsLimitMinusTotalDue() {
        #expect(card(billed: 12000, unbilled: 3500, limit: 100_000).remainingCredit == Money(84500))
    }

    @Test("剩餘額度最小是 0:刷超過額度時不顯示負數(web 的 Math.max(0, …))")
    func remainingCreditIsNeverNegative() {
        #expect(card(billed: 18000, unbilled: 5000, limit: 20000).remainingCredit == .zero)
    }

    @Test("沒有設定信用額度、或信用額度是 0 時，沒有剩餘額度", arguments: [nil, Decimal(0)])
    func noLimitMeansNoRemainingCredit(limit: Decimal?) {
        #expect(card(billed: 12000, unbilled: 3500, limit: limit).remainingCredit == nil)
    }
}
