import MyMoneyDomain
import SwiftUI

/// 年月快速切換「‹ 2026年10月 ›」(交易頁 #130、統計頁 #164 共用):左右是上一月、下一月，中間點開選任意年與月。
/// 兩頁長得一樣、行為一樣;按鈕的 identifier 用 `identifierPrefix`(例如 `transactions.month`)。
struct MonthPill: View {
    let identifierPrefix: String
    /// 所選的月份文字，例如「2026年10月」(VoiceOver 的值)。
    let title: String
    let selected: CalendarMonth
    /// 選擇器的最晚月份(通常是本月)。
    let latest: CalendarMonth
    var canGoToNext = true
    let previous: () -> Void
    let next: () -> Void
    let select: (CalendarMonth) -> Void
    @State private var isPickerPresented = false

    var body: some View {
        // 年月文字照系統字級、不縮小(#156):一行放不下(無障礙字級)就改成年月在上、上一月與下一月在下。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                previousButton
                titleButton
                nextButton
            }
            VStack(spacing: 0) {
                titleButton
                HStack(spacing: 0) {
                    previousButton
                    nextButton
                }
            }
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $isPickerPresented) {
            MonthPickerSheet(selected: selected, latest: latest, identifierPrefix: identifierPrefix, onSelect: select)
        }
    }

    private var previousButton: some View {
        Button(action: previous) {
            Image(systemName: "chevron.left")
                .fontWeight(.semibold)
                .frame(width: 48, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("上一月")
        .accessibilityIdentifier("\(identifierPrefix).previous")
    }

    private var titleButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            Text(title)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("選擇年月")
        .accessibilityValue(title)
        .accessibilityIdentifier("\(identifierPrefix).title")
    }

    private var nextButton: some View {
        Button(action: next) {
            Image(systemName: "chevron.right")
                .fontWeight(.semibold)
                .frame(width: 48, height: 44)
                .contentShape(.rect)
        }
        .disabled(!canGoToNext)
        .accessibilityLabel("下一月")
        .accessibilityIdentifier("\(identifierPrefix).next")
    }
}

/// 選年與月的 sheet:兩個滾輪(年、月)，最晚到本月。
private struct MonthPickerSheet: View {
    let latest: CalendarMonth
    let identifierPrefix: String
    let onSelect: (CalendarMonth) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int

    init(selected: CalendarMonth, latest: CalendarMonth, identifierPrefix: String, onSelect: @escaping (CalendarMonth) -> Void) {
        self.latest = latest
        self.identifierPrefix = identifierPrefix
        self.onSelect = onSelect
        // 滾輪裡沒有的年月(例如自訂範圍落在十年前)改成最接近的，不然滾輪沒有選取值。
        let year = min(max(selected.year, latest.year - 10), latest.year)
        _year = State(initialValue: year)
        _month = State(initialValue: min(selected.month, year == latest.year ? latest.month : 12))
    }

    private var years: [Int] { Array((latest.year - 10)...latest.year) }
    /// 最晚的那一年只到本月。
    private var months: [Int] { Array(1...(year == latest.year ? latest.month : 12)) }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    // verbatim:`Text("\(Int)")` 會依地區加千分位，變成「2,025年」。
                    ForEach(years, id: \.self) { Text(verbatim: "\($0)年").tag($0) }
                }
                .accessibilityIdentifier("\(identifierPrefix).yearWheel")
                Picker("月", selection: $month) {
                    ForEach(months, id: \.self) { Text(verbatim: "\($0)月").tag($0) }
                }
                .accessibilityIdentifier("\(identifierPrefix).monthWheel")
            }
            .wheelPickerStyle()
            .padding(.horizontal)
            .onChange(of: year) { _, _ in
                // 切到最晚的那一年時，月份不能超過本月。
                month = min(month, months.last ?? 1)
            }
            .navigationTitle("選擇年月")
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("完成", identifier: "\(identifierPrefix).done") {
                    onSelect(CalendarMonth(year: year, month: month))
                    dismiss()
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}
