import Charts
import MyMoneyDomain
import SwiftUI

/// 交易頁最上面的主視覺(#118):超大的淨收支(目前篩選區間)，旁邊是收入與支出，
/// 下面是「支出佔收入」的比例條(收入是 0 時不顯示)和本區間每日支出長條圖(突顯最大的一天)。
/// 系統分類(信用卡還款等)照舊排除在合計之外。
struct TransactionsHero: View {
    let model: TransactionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            numbers
            if let ratio = model.expenseRatio {
                ExpenseRatioBar(ratio: ratio, summary: model.expenseRatioSummary ?? "")
            }
            if model.hasDailyExpenses {
                DailyExpenseChart(
                    days: model.dailyExpenses, summary: model.dailyExpenseSummary, startText: model.rangeStartText,
                    endText: model.rangeEndText, dayText: model.dayText
                )
            }
        }
        .padding(.vertical, 8)
    }

    /// 淨收支的大數字，收入與支出在旁邊;放不下時改成上下堆疊，再放不下收入與支出也上下堆疊。
    private var numbers: some View {
        let net = BigNumber(title: "淨收支", amount: model.net)
        let income = stat("收入", model.totalIncome, text: "+\(model.totalIncome.formatted())", color: .green)
        let expense = stat("支出", model.totalExpense, text: "-\(model.totalExpense.formatted())", color: .red)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                net
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    income
                    expense
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                net
                HStack(spacing: 24) {
                    income
                    expense
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                net
                income
                expense
            }
        }
    }

    private func stat(_ title: String, _ amount: Money, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(amount.spokenText)
    }
}

/// 支出佔收入的比例條:標題、百分比與一條進度條;超過 100% 時條是滿的，百分比照實顯示。
struct ExpenseRatioBar: View {
    let ratio: Double
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("支出佔收入")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(ratio, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(ratio > 1 ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            }
            ProgressView(value: min(ratio, 1))
                .tint(.red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}

/// 本區間每日支出的長條圖:最大的一天用紅色並標出金額，其他天淡色;不畫座標軸，只在左下、右下標區間起迄日。
struct DailyExpenseChart: View {
    let days: [DailyExpense]
    let summary: String?
    let startText: String
    let endText: String
    let dayText: (CalendarDay) -> String

    var body: some View {
        VStack(spacing: 4) {
            Chart(days) { day in
                BarMark(x: .value("日期", day.date.startOfDay, unit: .day), y: .value("支出", day.amount.chartValue))
                    .foregroundStyle(day.isPeak ? Color.red : Color.red.opacity(0.3))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if day.isPeak {
                            Text(day.amount.formatted())
                                .font(.footnote.bold())
                                .monospacedDigit()
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityLabel(dayText(day.date))
                    .accessibilityValue("支出 \(day.amount.spokenText)")
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            // 最大的一天上面要留空間給金額標註，不然標註會超出圖的上緣。
            .chartYScale(domain: 0...(days.map { $0.amount.chartValue }.max() ?? 1) * 1.3)
            .frame(height: 110)
            .accessibilityLabel(summary ?? "本區間每日支出")

            HStack {
                Text(startText)
                Spacer()
                Text(endText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}
