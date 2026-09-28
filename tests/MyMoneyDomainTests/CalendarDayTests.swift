import Foundation
import MyMoneyDomain
import Testing

@Suite("日期(台灣時間的「今天」與 YYYY-MM-DD)")
struct CalendarDayTests {
    private func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    /// web 以前用 UTC 算「今天」,台灣時間 00:00 到 07:59 會錯成前一天(parity 刻意偏離第 3 項)。
    @Test(
        "今天以台灣時間計算",
        arguments: [
            ("2026-09-27T16:30:00Z", "2026-09-28"),
            ("2026-09-27T15:59:59Z", "2026-09-27"),
            ("2026-09-27T23:59:59Z", "2026-09-28"),
            ("2026-12-31T16:00:00Z", "2027-01-01"),
        ]
    )
    func todayInTaipei(now: String, expected: String) {
        #expect(CalendarDay.today(now: instant(now)).iso == expected)
    }

    @Test("YYYY-MM-DD 可以互轉")
    func isoRoundTrip() {
        #expect(CalendarDay(iso: "2026-09-05")?.iso == "2026-09-05")
        #expect(CalendarDay(iso: "2026-09-05") == CalendarDay(year: 2026, month: 9, day: 5))
        #expect(CalendarDay(iso: "not-a-date") == nil)
    }

    /// DatePicker 用 `Date`;一律以台灣時間的午夜互轉，跨時區也不會差一天。
    @Test("跟 Date 互轉(台灣時間)")
    func dateRoundTrip() {
        let day = CalendarDay(year: 2026, month: 9, day: 28)

        #expect(CalendarDay(date: day.startOfDay) == day)
        #expect(day.startOfDay == instant("2026-09-27T16:00:00Z"))
    }

    @Test("本月 1 號")
    func firstOfMonth() {
        #expect(CalendarDay(year: 2026, month: 9, day: 28).firstOfMonth == CalendarDay(year: 2026, month: 9, day: 1))
    }

    @Test("依日期先後比較")
    func ordering() {
        #expect(CalendarDay(year: 2026, month: 9, day: 5) < CalendarDay(year: 2026, month: 9, day: 27))
        #expect(CalendarDay(year: 2026, month: 8, day: 31) < CalendarDay(year: 2026, month: 9, day: 1))
    }
}
