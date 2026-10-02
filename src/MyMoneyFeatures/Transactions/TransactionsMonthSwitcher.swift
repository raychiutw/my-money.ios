import MyMoneyDomain
import SwiftUI

/// 交易頁頂端的年月快速切換(#130):「‹ 2026年10月 ›」。左右是上一月、下一月，中間點開選任意年與月。
/// 切換等同改篩選的起迄日(視角、類型、分類不變)，跟篩選 sheet 共用同一份狀態。下一月在本月時停用(不能看未來)。
struct MonthPill: View {
    let model: TransactionsModel
    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.goToPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .frame(width: 48, height: 44)
            }
            .accessibilityLabel("上一月")
            .accessibilityIdentifier("transactions.month.previous")

            Button {
                isPickerPresented = true
            } label: {
                Text(model.monthTitle)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("選擇年月")
            .accessibilityValue(model.monthTitle)
            .accessibilityIdentifier("transactions.month.title")

            Button {
                Task { await model.goToNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
                    .frame(width: 48, height: 44)
            }
            .disabled(!model.canGoToNextMonth)
            .accessibilityLabel("下一月")
            .accessibilityIdentifier("transactions.month.next")
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $isPickerPresented) {
            MonthPickerSheet(selected: model.selectedMonth ?? CalendarMonth(model.filter.to), latest: model.currentMonth) { month in
                Task { await model.selectMonth(month) }
            }
        }
    }
}

/// 選年與月的 sheet:兩個滾輪(年、月)，最晚到本月。
private struct MonthPickerSheet: View {
    let latest: CalendarMonth
    let onSelect: (CalendarMonth) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int

    init(selected: CalendarMonth, latest: CalendarMonth, onSelect: @escaping (CalendarMonth) -> Void) {
        self.latest = latest
        self.onSelect = onSelect
        _year = State(initialValue: min(selected.year, latest.year))
        _month = State(initialValue: selected.month)
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
                .accessibilityIdentifier("transactions.month.yearWheel")
                Picker("月", selection: $month) {
                    ForEach(months, id: \.self) { Text(verbatim: "\($0)月").tag($0) }
                }
                .accessibilityIdentifier("transactions.month.monthWheel")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSelect(CalendarMonth(year: year, month: month))
                        dismiss()
                    }
                    .accessibilityIdentifier("transactions.month.done")
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}
