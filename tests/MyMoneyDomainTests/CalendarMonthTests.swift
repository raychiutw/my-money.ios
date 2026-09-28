import MyMoneyDomain
import Testing

@Suite("年月(YYYY-MM)")
struct CalendarMonthTests {
    @Test("YYYY-MM 可以互轉")
    func isoRoundTrip() {
        #expect(CalendarMonth(year: 2026, month: 9).iso == "2026-09")
        #expect(CalendarMonth(iso: "2026-09") == CalendarMonth(year: 2026, month: 9))
        #expect(CalendarMonth(iso: "2026-13") == nil)
        #expect(CalendarMonth(iso: "2026-9") == nil)
    }

    @Test("日期所在的月份")
    func fromDay() {
        #expect(CalendarMonth(CalendarDay(year: 2026, month: 9, day: 28)) == CalendarMonth(year: 2026, month: 9))
    }

    @Test("上一個月與下一個月會跨年")
    func previousAndNext() {
        #expect(CalendarMonth(year: 2026, month: 1).previous == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2025, month: 12).next == CalendarMonth(year: 2026, month: 1))
        #expect(CalendarMonth(year: 2026, month: 9).next == CalendarMonth(year: 2026, month: 10))
    }

    @Test("依時間先後比較")
    func ordering() {
        #expect(CalendarMonth(year: 2025, month: 12) < CalendarMonth(year: 2026, month: 1))
        #expect(!(CalendarMonth(year: 2026, month: 2) < CalendarMonth(year: 2026, month: 1)))
    }
}
