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

    @Test("沒有設定信用額度時，沒有剩餘額度")
    func noLimitMeansNoRemainingCredit() {
        #expect(card(billed: 12000, unbilled: 3500, limit: nil).remainingCredit == nil)
    }

    @Test(
        "剩餘額度低於 10,000 時要警示(跟 web 一樣，剛好 10,000 不警示)",
        arguments: [
            (Decimal(8000), Decimal(5000), Decimal(20000), true),
            (Decimal(5000), Decimal(5000), Decimal(20000), false),
            (Decimal(12000), Decimal(3500), Decimal(100_000), false),
        ]
    )
    func lowCreditWarning(billed: Decimal, unbilled: Decimal, limit: Decimal, expected: Bool) {
        #expect(card(billed: billed, unbilled: unbilled, limit: limit).isLowOnCredit == expected)
    }

    @Test("沒有設定信用額度時不警示")
    func noLimitIsNotLowOnCredit() {
        #expect(!card(billed: 99000, unbilled: 0, limit: nil).isLowOnCredit)
    }
}
