import Foundation
import MyMoneyDomain

// 畫面上的日期(DESIGN.md「日期」):一律用系統依地區的格式(`Date.FormatStyle`),時區固定台灣;
// wire 上照舊是 `YYYY-MM-DD`(`CalendarDay.iso`)。
//
// locale 和曆法跟著系統，跟 DatePicker 一樣：使用者把曆法設成民國曆，兩邊一起變。
// 畫面 model 產生日期字串，測試注入固定的 locale 和今天。

extension Date.FormatStyle {
    /// 台灣時間、跟著 `locale` 的曆法。
    static func taipei(_ locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: locale.calendar, timeZone: CalendarDay.timeZone)
    }
}

extension CalendarDay {
    /// 清單裡的日期，例如「2026年9月29日」;跟今天同一年時省略年份，例如「9月29日」。
    func text(today: CalendarDay, locale: Locale) -> String {
        let style = Date.FormatStyle.taipei(locale)
        return startOfDay.formatted(year == today.year ? style.month().day() : style.year().month().day())
    }

    /// 交易頁的分組標頭，例如「9月29日週二」;不是今年的加上年份，例如「2025年12月31日週三」。
    func headerText(today: CalendarDay, locale: Locale) -> String {
        let style = Date.FormatStyle.taipei(locale)
        return startOfDay.formatted(year == today.year ? style.month().day().weekday() : style.year().month().day().weekday())
    }
}

extension Date {
    /// 清單裡的日期(台灣時間的那一天),規則同 `CalendarDay.text(today:locale:)`。
    func dayText(today: CalendarDay, locale: Locale) -> String {
        CalendarDay(date: self).text(today: today, locale: locale)
    }

    /// 日期加時間(台灣時間),例如「10月6日 下午3:00」;不是今年的加上年份。
    func dateTimeText(today: CalendarDay, locale: Locale) -> String {
        let style = Date.FormatStyle.taipei(locale)
        let date = CalendarDay(date: self).year == today.year ? style.month().day() : style.year().month().day()
        return formatted(date.hour().minute())
    }
}

extension CalendarMonth {
    /// 月份，例如「2026年9月」。
    func text(locale: Locale) -> String {
        firstDay.formatted(Date.FormatStyle.taipei(locale).year().month())
    }

    /// 年份，例如「2026年」。
    func yearText(locale: Locale) -> String {
        firstDay.formatted(Date.FormatStyle.taipei(locale).year())
    }

    private var firstDay: Date {
        CalendarDay(year: year, month: month, day: 1).startOfDay
    }
}
