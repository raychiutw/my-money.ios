import Foundation
import MyMoneyDomain

/// 總覽「走勢」圖(60 天)的呈現資料(#116):後端算好的每日預測餘額，加上畫圖需要的零線位置與 VoiceOver 摘要。
/// 只整理後端的值，不重算任何業務規則(CLAUDE.md「規則」)。
public struct ForecastTrend: Sendable {
    public struct Point: Hashable, Sendable {
        /// 第幾天(0 是今天)。
        public let index: Int
        public let date: CalendarDay
        public let balance: Double
    }

    public let points: [Point]
    public let minimum: Double
    public let maximum: Double
    /// 後端判斷的透支風險(最低餘額低於 0)。
    public let willOverdraft: Bool

    private let minBalance: Money
    private let minDate: CalendarDay?

    public init(forecast: CashFlowForecast) {
        points = forecast.dailyBalances.enumerated().map { index, day in
            Point(index: index, date: day.date, balance: day.balance.chartValue)
        }
        minimum = points.map(\.balance).min() ?? 0
        maximum = points.map(\.balance).max() ?? 0
        willOverdraft = forecast.willOverdraft
        minBalance = forecast.minBalance
        minDate = forecast.minDate
    }

    /// 線有跨過零線:有一段在零以上、有一段在零以下。
    public var crossesZero: Bool { minimum < 0 && maximum > 0 }

    /// 整條線都在零以下。
    public var isEntirelyBelowZero: Bool { !points.isEmpty && maximum < 0 }

    /// 零線在線的上下範圍裡由上往下的位置(0 到 1)，紅色從這裡開始;沒有跨過零線時是 `nil`
    /// (全在零以上是一般色，全在零以下整條紅色)。
    public var zeroFraction: Double? {
        crossesZero ? maximum / (maximum - minimum) : nil
    }

    /// 走勢圖右下的標籤,例如「60 天後」。
    public static var endLabel: String { "\(ForecastHorizon.days) 天後" }

    /// 給 VoiceOver 念的一句話:最低餘額、發生的日期、會不會透支。顏色之外，透支也用文字說出來(不只靠顏色)。
    public func spokenSummary(today: CalendarDay, locale: Locale) -> String {
        var parts = ["未來 \(ForecastHorizon.days) 天預測餘額", "最低餘額 \(minBalance.spokenText)"]
        if let minDate {
            parts.append(minDate.text(today: today, locale: locale))
        }
        parts.append(willOverdraft ? "會透支" : "不會透支")
        return parts.joined(separator: "，")
    }
}
