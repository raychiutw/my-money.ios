import MyMoneyDomain
import MyMoneyFeatures
import Testing

@Suite("輸入的金額是整數")
struct AmountParsingTests {
    /// `Decimal(string:)` 會只讀到第一個看不懂的字元為止：貼上「1,000」會變成 1、「12abc」變成 12。
    @Test("整個字串都是數字才算數", arguments: [
        ("1000", Money(1000) as Money?),
        (" 1000 ", Money(1000)),
        ("0", .zero),
        ("1,000", nil),
        ("12.5", nil),
        ("12abc", nil),
        ("1e3", nil),
        ("-5", nil),
        ("", nil),
    ])
    func wholeNumber(text: String, expected: Money?) {
        #expect(Money(wholeNumber: text) == expected)
    }
}
