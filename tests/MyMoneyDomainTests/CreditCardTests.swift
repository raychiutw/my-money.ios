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

    @Test("結帳日出帳結轉：有結帳日、有未出帳金額，而且今天(台灣時間)已經到了結帳日", arguments: [
        (15, Decimal(3500), 15, true),
        (15, Decimal(3500), 28, true),
        (15, Decimal(3500), 14, false),
        (15, Decimal(0), 28, false),
    ])
    func statementDue(statementDay: Int, unbilled: Decimal, today: Int, expected: Bool) {
        let card = CreditCard(
            id: AccountID("card"), name: "測試卡", colorHex: "#FFD4A0", billedDebt: Money(12000), unbilledDebt: Money(unbilled),
            creditLimit: nil, statementDay: statementDay, paymentDueDay: 5
        )

        #expect(card.isStatementDue(today: CalendarDay(year: 2026, month: 9, day: today)) == expected)
    }

    /// web 用 `getDate() >= statement_day`,結帳日 31 號的卡在 2 月、4 月永遠不會提醒(parity 刻意偏離第 32 項)。
    @Test("結帳日是 29 到 31 號時，較短的月份以月底當結帳日", arguments: [
        (31, 2026, 2, 28, true),
        (30, 2026, 2, 27, false),
        (31, 2026, 4, 30, true),
        (31, 2026, 4, 29, false),
        (29, 2028, 2, 29, true),
    ])
    func shortMonths(statementDay: Int, year: Int, month: Int, day: Int, expected: Bool) {
        let card = CreditCard(
            id: AccountID("card"), name: "測試卡", colorHex: "#FFD4A0", billedDebt: .zero, unbilledDebt: Money(100),
            creditLimit: nil, statementDay: statementDay, paymentDueDay: nil
        )

        #expect(card.isStatementDue(today: CalendarDay(year: year, month: month, day: day)) == expected)
    }

    @Test("沒有結帳日時不提醒結轉")
    func noStatementDay() {
        let card = CreditCard(
            id: AccountID("card"), name: "測試卡", colorHex: "#FFD4A0", billedDebt: .zero, unbilledDebt: Money(100),
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )

        #expect(!card.isStatementDue(today: CalendarDay(year: 2026, month: 9, day: 28)))
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
