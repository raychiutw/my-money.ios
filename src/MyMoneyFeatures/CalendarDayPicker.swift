import MyMoneyDomain
import SwiftUI

extension View {
    /// 綁定 `CalendarDay` 的 DatePicker 用台灣時間顯示。`CalendarDay.startOfDay` 是台灣時間的午夜，
    /// 裝置在別的時區時不設定，會顯示成前一天(CI 的模擬器是 UTC,台灣 9/28 顯示成 9/27)。
    func calendarDayTimeZone() -> some View {
        environment(\.timeZone, CalendarDay.timeZone)
    }
}
