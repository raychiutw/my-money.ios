import Foundation
import MyMoneyDomain

extension Money {
    /// 跟 web 的 `formatCurrency` 一樣：新台幣、千分位、0 位小數，例如 `$1,234`、`-$1,500`。
    ///
    /// 固定用 zh_Hant_TW,不跟著裝置的語系走(web 也寫死 `zh-TW`)。捨入要明確指定 away from zero:
    /// Foundation 預設四捨六入五成雙(2.5 → $2),web 的 `Intl` 是 halfExpand(2.5 → $3)。
    public func formatted() -> String {
        amount.formatted(Self.style)
    }

    /// 給 VoiceOver 念的金額，例如「50,000 元」「負 1,500 元」。
    public var spokenText: String {
        let magnitude = abs(amount).formatted(Self.spokenNumberStyle)
        return amount < 0 ? "負 \(magnitude) 元" : "\(magnitude) 元"
    }

    private static let spokenNumberStyle = Decimal.FormatStyle(locale: Locale(identifier: "zh_Hant_TW"))
        .precision(.fractionLength(0))
        .rounded(rule: .toNearestOrAwayFromZero)

    private static let style = Decimal.FormatStyle.Currency(code: "TWD", locale: Locale(identifier: "zh_Hant_TW"))
        .precision(.fractionLength(0))
        .rounded(rule: .toNearestOrAwayFromZero)
}
