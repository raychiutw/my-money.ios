import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import Testing

@Suite("金額的顯示格式(跟 web 的 formatCurrency 一致)")
struct MoneyFormatTests {
    @Test(
        "新台幣、千分位、0 位小數",
        arguments: [
            (Decimal(1234), "$1,234"),
            (Decimal(1_234_567), "$1,234,567"),
            (Decimal(0), "$0"),
            (Decimal(-1500), "-$1,500"),
        ]
    )
    func formatsLikeWeb(amount: Decimal, expected: String) {
        #expect(Money(amount).formatted() == expected)
    }

    /// Foundation 預設四捨六入五成雙(2.5 → $2);web 的 Intl 是 halfExpand(2.5 → $3)。
    @Test(
        "捨入跟 web 一樣是 away from zero",
        arguments: [
            (Decimal(string: "2.5")!, "$3"),
            (Decimal(string: "3.5")!, "$4"),
            (Decimal(string: "99.5")!, "$100"),
            (Decimal(string: "-2.5")!, "-$3"),
            (Decimal(string: "2.4")!, "$2"),
        ]
    )
    func roundsAwayFromZero(amount: Decimal, expected: String) {
        #expect(Money(amount).formatted() == expected)
    }

    /// 畫面上的 `$` 會被 VoiceOver 念成「美元」,所以另外提供念給人聽的文字。
    @Test(
        "VoiceOver 念的金額用「元」,負數念「負」",
        arguments: [
            (Decimal(50000), "50,000 元"),
            (Decimal(0), "0 元"),
            (Decimal(-1500), "負 1,500 元"),
            (Decimal(string: "2.5")!, "3 元"),
        ]
    )
    func spokenText(amount: Decimal, expected: String) {
        #expect(Money(amount).spokenText == expected)
    }
}
