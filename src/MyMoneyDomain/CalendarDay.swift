import Foundation

/// 一個日曆日(沒有時間)。wire 上是 `YYYY-MM-DD`。
///
/// 「今天」一律用台灣時間(Asia/Taipei)計算，跟家庭群組的其他成員一致(CLAUDE.md「規則」)。
public struct CalendarDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`;格式不對時是 `nil`。
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var firstOfMonth: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }

    /// `date` 在台灣時間是哪一天。
    public init(date: Date) {
        let parts = Self.taipeiCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// 這一天台灣時間的午夜。
    public var startOfDay: Date {
        Self.taipeiCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 台灣時間的今天。
    public static func today(now: Date = Date()) -> CalendarDay {
        CalendarDay(date: now)
    }

    /// 台灣時間。畫面上的 DatePicker 也要用它，不然裝置在別的時區時，`startOfDay` 會顯示成前一天。
    public static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    private static let taipeiCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
