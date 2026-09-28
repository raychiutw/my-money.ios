import Foundation
import MyMoneyDomain

extension Money {
    /// 使用者輸入的整數金額(前後空白不算)。有任何不是 0 到 9 的字元就是 `nil`,例如千分位的逗號、小數點、負號。
    ///
    /// 不直接用 `Decimal(string:)`:它讀到第一個看不懂的字元就停，貼上「1,000」會變成 1、「12abc」變成 12。
    public init?(wholeNumber text: String) {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !digits.isEmpty,
            digits.allSatisfy({ ("0"..."9").contains($0) }),
            let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return nil
        }
        self.init(value)
    }
}

extension Decimal {
    /// 百分比文字，固定用 `.` 當小數點(web 的 `toFixed`),不跟著裝置語系走，例如「15%」「2.5%」。
    func percentText(fractionDigits: Int) -> String {
        let style = Decimal.FormatStyle.number
            .precision(.fractionLength(fractionDigits))
            .rounded(rule: .toNearestOrAwayFromZero)
            .locale(Locale(identifier: "en_US_POSIX"))
        return "\(formatted(style))%"
    }
}

extension CalendarDay {
    /// 例如「2026/10/05」。直接用年月日，不經過時區換算。
    var slashText: String {
        String(format: "%d/%02d/%02d", year, month, day)
    }
}
