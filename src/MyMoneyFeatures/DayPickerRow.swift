import MyMoneyDomain
import SwiftUI

/// 表單裡的日期列(#161)——記一筆與編輯、ATM 提款／轉帳、信用卡還款、報銷、儲蓄目標的截止日、記帳篩選的起日與迄日共用。
///
/// 一般字級是系統的 compact `DatePicker`。最大的無障礙字級下,compact 的膠囊比卡片還寬,「日期」標籤和日期文字兩側被切掉,
/// 而且它是系統控制項,不能折行、也不能縮小(字級不縮小,DESIGN.md「字型與數字」);所以無障礙字級改成
/// 「標籤在上、日期文字在下」的一列(文字可以折行),點了開一個有圖形日曆的 sheet(日曆用整個螢幕寬,不受卡片限制)。
/// 日期一律用台灣時間(`calendarDayTimeZone`)。
struct DayPickerRow: View {
    let title: String
    @Binding var day: CalendarDay
    /// 最早可選的一天(迄日不早於起日);沒有就不限。
    var minimum: CalendarDay?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var isPresenting = false

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibleRow
        } else {
            picker(style: .compact)
        }
    }

    private var date: Binding<Date> {
        Binding(get: { day.startOfDay }, set: { day = CalendarDay(date: $0) })
    }

    @ViewBuilder
    private func picker(style: some DatePickerStyle) -> some View {
        Group {
            if let minimum {
                DatePicker(title, selection: date, in: minimum.startOfDay..., displayedComponents: .date)
            } else {
                DatePicker(title, selection: date, displayedComponents: .date)
            }
        }
        .datePickerStyle(style)
        .calendarDayTimeZone()
    }

    private var accessibleRow: some View {
        Button {
            isPresenting = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(dayText)
                    .foregroundStyle(Color.ciText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(dayText)
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $isPresenting) {
            NavigationStack {
                picker(style: .graphical)
                    .padding()
                    .navigationTitle(title)
                    .inlineNavigationTitle()
                    .toolbar {
                        SheetConfirmButton("完成", identifier: "dayPicker.done") { isPresenting = false }
                    }
            }
            .presentationDetents([.large])
        }
    }

    /// 完整的日期，例如「2026年10月4日」(系統格式、台灣時間;跟 compact 膠囊上的字一樣)。
    private var dayText: String {
        day.startOfDay.formatted(Date.FormatStyle.taipei(locale).year().month().day())
    }
}
