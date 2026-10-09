import Foundation
import SwiftUI
import MyMoneyDomain

extension Money {
    /// 跟 web 的 `formatCurrency` 一樣：新台幣、千分位、0 位小數，例如 `$1,234`、`−$1,500`。
    /// 負號用 U+2212「−」(#202),全 app 統一;跟 web 不同的只有這個字元。
    ///
    /// 固定用 zh_Hant_TW,不跟著裝置的語系走(web 也寫死 `zh-TW`)。捨入要明確指定 away from zero:
    /// Foundation 預設四捨六入五成雙(2.5 → $2),web 的 `Intl` 是 halfExpand(2.5 → $3)。
    public func formatted() -> String {
        let text = amount.formatted(Self.style)
        return text.hasPrefix("-") ? "−" + text.dropFirst() : text
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

extension Money {
    /// Swift Charts 只吃 `Double`;只用來畫圖，不拿來計算。
    var chartValue: Double { NSDecimalNumber(decimal: amount).doubleValue }
}


/// 一筆金額的方向(#202):錢出去(支出、扣款、還款、欠款)或錢進來(收入、入帳)。
/// 後端的支出與待繳金額是正數,方向由顯示的地方決定。
public enum AmountFlow: Sendable {
    case outflow
    case inflow
}

/// 金額的顏色角色(#202):負數紅、正數綠、零一般文字色。
public enum AmountTone: Hashable, Sendable {
    case negative
    case positive
    case neutral

    /// 沒有顏色(一般文字色)時是 `nil`。
    public var color: Color? {
        switch self {
        case .negative: .red
        case .positive: .green
        case .neutral: nil
        }
    }
}

extension Money {
    /// 流量的帶號文字:錢出去「−$120」、錢進來「+$45,000」,零不帶號。只看大小,方向由 `flow` 決定。
    public func formatted(flow: AmountFlow) -> String {
        let magnitude = Money(abs(amount))
        guard magnitude != .zero else { return magnitude.formatted() }
        return (flow == .outflow ? "−" : "+") + magnitude.formatted()
    }

    /// 淨額的帶號文字:依自己的正負,正數「+$4,206」、負數「−$82,156」、零不帶號。
    public func signedFormatted() -> String {
        amount == 0 ? formatted() : formatted(flow: amount < 0 ? .outflow : .inflow)
    }

    /// 依自己的正負的顏色角色。
    public var tone: AmountTone {
        amount < 0 ? .negative : (amount > 0 ? .positive : .neutral)
    }

    /// 流量的顏色角色:金額是零時一般色,否則由方向決定。
    public func tone(of flow: AmountFlow) -> AmountTone {
        amount == 0 ? .neutral : (flow == .outflow ? .negative : .positive)
    }
}

/// 一個金額在畫面上的呈現(#208):文字、顏色角色與 VoiceOver 念法一次決定。
///
/// 數字磚、卡片、摘要列、金額列、大數字只收這個結果,不再各自配對「文字、顏色、警示」(#202 的規則集中在這裡):
/// - `stock`:存量(餘額、可支配現金),原樣顯示,為負時紅色;
/// - `outflow`/`inflow`:流量與負債(支出、待繳、收入),帶 −/+、紅或綠,零不帶號;
/// - `net`:淨額,依自己的正負;
/// - `plain`:原樣、一般色(骨架佔位、不需要警示的數字)。
public struct AmountPresentation: Hashable, Sendable {
    public let amount: Money
    public let text: String
    public let tone: AmountTone

    /// VoiceOver 念的金額(不念符號:流量的方向由標籤與元件說明)。
    public var spokenText: String { amount.spokenText }

    private init(amount: Money, text: String, tone: AmountTone) {
        self.amount = amount
        self.text = text
        self.tone = tone
    }

    public static func plain(_ amount: Money) -> AmountPresentation {
        AmountPresentation(amount: amount, text: amount.formatted(), tone: .neutral)
    }

    public static func stock(_ amount: Money) -> AmountPresentation {
        AmountPresentation(amount: amount, text: amount.formatted(), tone: amount < .zero ? .negative : .neutral)
    }

    public static func outflow(_ amount: Money) -> AmountPresentation {
        AmountPresentation(amount: amount, text: amount.formatted(flow: .outflow), tone: amount.tone(of: .outflow))
    }

    public static func inflow(_ amount: Money) -> AmountPresentation {
        AmountPresentation(amount: amount, text: amount.formatted(flow: .inflow), tone: amount.tone(of: .inflow))
    }

    public static func net(_ amount: Money) -> AmountPresentation {
        AmountPresentation(amount: amount, text: amount.signedFormatted(), tone: amount.tone)
    }

    /// 顏色;一般色是 `nil`(沿用主要文字色)。
    var color: Color? { tone.color }
}
