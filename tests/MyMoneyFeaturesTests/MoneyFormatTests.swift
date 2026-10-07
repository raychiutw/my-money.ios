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
            (Decimal(-1500), "−$1,500"),
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
            (Decimal(string: "-2.5")!, "−$3"),
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


@Suite("金額的正負號與顏色(#202)")
struct AmountSignTests {
    @Test("錢出去是負數、錢進來是正數,零不帶號;符號用 U+2212", arguments: [
        (Decimal(120), AmountFlow.outflow, "−$120"), (Decimal(45000), .inflow, "+$45,000"),
        (Decimal(0), .outflow, "$0"), (Decimal(0), .inflow, "$0"),
        // 後端的待繳、支出金額是正數:方向由呼叫端說,負數的輸入也只看大小。
        (Decimal(-9178), .outflow, "−$9,178"), (Decimal(string: "2.5")!, .outflow, "−$3"),
    ])
    func flowText(amount: Decimal, flow: AmountFlow, expected: String) {
        #expect(Money(amount).formatted(flow: flow) == expected)
    }

    @Test("淨額依自己的正負:正數 +、負數 −、零不帶號", arguments: [
        (Decimal(4206), "+$4,206"), (Decimal(-82156), "−$82,156"), (Decimal(0), "$0"),
    ])
    func netText(amount: Decimal, expected: String) {
        #expect(Money(amount).signedFormatted() == expected)
    }

    @Test("顏色角色:負數紅、正數綠、零一般", arguments: [
        (Decimal(-1), AmountTone.negative), (Decimal(1), .positive), (Decimal(0), .neutral),
    ])
    func tone(amount: Decimal, expected: AmountTone) {
        #expect(Money(amount).tone == expected)
    }

    @Test("流量的方向決定顏色角色;金額是零時一般色")
    func flowTone() {
        #expect(Money(120).tone(of: .outflow) == .negative)
        #expect(Money(120).tone(of: .inflow) == .positive)
        #expect(Money.zero.tone(of: .outflow) == .neutral)
    }
}
