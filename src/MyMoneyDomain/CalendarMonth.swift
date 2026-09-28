import Foundation

/// 一個月份。wire 上是 `YYYY-MM`。
public struct CalendarMonth: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// 日期所在的月份。
    public init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    /// `YYYY-MM`;格式不對時是 `nil`。
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 2, parts[0].count == 4, parts[1].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
        else {
            return nil
        }
        self.init(year: year, month: month)
    }

    public var iso: String {
        String(format: "%04d-%02d", year, month)
    }

    public var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    public var next: CalendarMonth {
        month == 12 ? CalendarMonth(year: year + 1, month: 1) : CalendarMonth(year: year, month: month + 1)
    }

    public static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
