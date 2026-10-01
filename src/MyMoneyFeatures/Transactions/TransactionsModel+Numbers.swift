import Foundation
import MyMoneyDomain

/// 交易頁長條圖的一天:當日支出(不含系統分類，沒花錢的天是 0)。
public struct DailyExpense: Identifiable, Sendable {
    public let date: CalendarDay
    public let amount: Money
    /// 區間裡支出最大的一天;金額相同時取較早的一天，只有一天。
    public let isPeak: Bool

    public var id: CalendarDay { date }
}

/// 交易頁的數字優先主視覺(#118):支出佔收入的比例條與每日支出長條圖。
/// 資料都來自目前篩選之後的交易記錄，跟總收入、總支出同一個範圍(系統分類排除)。
extension TransactionsModel {
    /// 支出佔收入的比例(1 是 100%,可以超過);收入是 0 時是 `nil`，不顯示比例條。
    public var expenseRatio: Double? {
        guard totalIncome > .zero else { return nil }
        return NSDecimalNumber(decimal: totalExpense.amount / totalIncome.amount).doubleValue
    }

    /// 比例條的 VoiceOver 摘要，例如「支出佔收入百分之 2」。
    public var expenseRatioSummary: String? {
        guard let ratio = expenseRatio else { return nil }
        return "支出佔收入百分之 \((ratio * 100).rounded(.toNearestOrAwayFromZero).formatted(.number.precision(.fractionLength(0))))"
    }

    /// 篩選區間(起日到迄日)每一天的支出。
    public var dailyExpenses: [DailyExpense] {
        var totals: [CalendarDay: Money] = [:]
        for transaction in filtered where transaction.type == .expense && !transaction.isSystemRecord {
            totals[transaction.date, default: .zero] = (totals[transaction.date] ?? .zero) + transaction.amount
        }
        var days: [(CalendarDay, Money)] = []
        var day = filter.from
        while day <= filter.to {
            days.append((day, totals[day] ?? .zero))
            day = day.addingDays(1)
        }
        // 最大的一天;金額相同取較早的(`max(by:)` 在相等時保留先出現的那個，所以用「嚴格小於」比較)。
        let peak = days.max { $0.1 < $1.1 }.flatMap { $0.1 > .zero ? $0.0 : nil }
        return days.map { DailyExpense(date: $0.0, amount: $0.1, isPeak: $0.0 == peak) }
    }

    /// 區間裡有任何支出，才有長條圖。
    public var hasDailyExpenses: Bool { dailyExpenses.contains { $0.amount > .zero } }

    /// 長條圖的 VoiceOver 摘要，例如「本區間每日支出，最多的一天是9月5日，支出 300 元」;沒有支出時是 `nil`。
    public var dailyExpenseSummary: String? {
        guard let peak = dailyExpenses.first(where: \.isPeak) else { return nil }
        return "本區間每日支出，最多的一天是\(dayText(peak.date))，支出 \(peak.amount.spokenText)"
    }

    /// 長條圖左下、右下的日期標籤(區間起日與迄日)。
    public var rangeStartText: String { dayText(filter.from) }
    public var rangeEndText: String { dayText(filter.to) }

    /// 清單格式的日期，例如「9月28日」。
    public func dayText(_ day: CalendarDay) -> String {
        day.text(today: todayValue, locale: localeValue)
    }
}
