import Charts
import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 現金流預測：透支風險、最低餘額、預定收支、30 天逐日餘額與購買力試算(parity.md「現金流預測」)。
struct ForecastScreen: View {
    @Bindable var model: ForecastModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
    }

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("現金流預測")
            .task(id: model.dataVersion.value) {
                await model.refreshIfStale()
            }
            .keyboardDismissal(clearing: $focusedField)
            .onChange(of: model.purchaseError) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (model.phase, model.forecast) {
        case (.failed(let message), _):
            ContentUnavailableView {
                Label("無法載入現金流預測", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                GlassCapsuleButton(title: "重試") {
                    Task { await model.load() }
                }
            }
        case (_, .some(let forecast)):
            List {
                summarySection(forecast)
                chartSection(forecast)
                eventsSection(forecast)
                purchaseSection
            }
            .refreshable { await model.load() }
        case (_, .none):
            // 資料回來之前不顯示「安全」或 $0,改顯示骨架屏(parity 刻意偏離第 7 項)。
            List {
                SkeletonSection(count: 3, announces: true) { SkeletonSummaryRow() }
                SkeletonSection(title: "未來 30 天逐日餘額", count: 1) { SkeletonChart() }
                SkeletonSection(title: "預定收支", count: 3) { SkeletonItemRow() }
            }
        }
    }

    private func summarySection(_ forecast: CashFlowForecast) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(forecast.riskTitle)
                        .font(.headline)
                    // 只留透支的警告;安全時不另外解釋(DESIGN.md「說明文字」第 2 類)。
                    if forecast.willOverdraft {
                        Text("預計餘額會跌破 0,請及早調整")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: forecast.willOverdraft ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(forecast.willOverdraft ? .red : .green)
            }
            .accessibilityElement(children: .combine)
            SummaryRow(
                title: "最低餘額",
                amount: forecast.minBalance,
                detail: forecast.minDate == nil ? model.minDateText(of: forecast) : "發生在 \(model.minDateText(of: forecast))",
                warnsWhenNegative: true
            )
            LabeledContent("未來 30 天的預定收支", value: "\(forecast.events.count) 筆")
        }
    }

    private func chartSection(_ forecast: CashFlowForecast) -> some View {
        Section("未來 30 天逐日餘額") {
            Chart(forecast.dailyBalances, id: \.date) { day in
                AreaMark(x: .value("日期", day.date.startOfDay), y: .value("餘額", day.balance.chartValue))
                    .foregroundStyle(.tint.opacity(0.2))
                    .accessibilityHidden(true)
                LineMark(x: .value("日期", day.date.startOfDay), y: .value("餘額", day.balance.chartValue))
                    .accessibilityLabel(model.dateText(day.date))
                    .accessibilityValue("餘額 \(day.balance.spokenText)")
                if forecast.willOverdraft {
                    RuleMark(y: .value("零", 0))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
            }
            // x 軸用台灣時間(#77,洛杉磯時區的截圖證實):資料點是台灣時間的午夜，裝置在別的時區時，
            // 刻度會偏到前一天，預設的日期標籤也照裝置時區格式化。刻度位置依 environment 的 calendar
            // (曆法沿用系統設定，只換時區;只設 timeZone 沒有作用),標籤自己用台灣時間的日期。
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(model.dateText(CalendarDay(date: date)))
                        }
                    }
                }
            }
            .environment(\.calendar, taipeiCalendar)
            .frame(height: 220)
            .padding(.vertical, 8)
        }
    }

    private var taipeiCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = CalendarDay.timeZone
        return calendar
    }

    private func eventsSection(_ forecast: CashFlowForecast) -> some View {
        Section("預定收支") {
            if forecast.events.isEmpty {
                Text("未來 30 天沒有預定收支")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(forecast.events.enumerated()), id: \.offset) { _, event in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name)
                        Text(model.dateText(event.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(event.type == .income ? "+\(event.amount.formatted())" : "-\(event.amount.formatted())")
                        .monospacedDigit()
                        .foregroundStyle(event.type == .income ? .green : .red)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(event.name),\(model.dateText(event.date)),\(event.type == .income ? "收入" : "支出") \(event.amount.spokenText)"
                )
            }
        }
    }

    private var purchaseSection: some View {
        Section("購買力試算") {
            LabeledContent("購買金額") {
                AmountField(
                    "購買金額", text: $model.purchaseAmountText, prompt: Text("例如：25000"),
                    focus: $focusedField, equals: .amount, identifier: "forecast.purchaseAmount"
                )
            }
            PrimaryCapsuleButton(title: "進行購買力試算", fillsWidth: true) {
                focusedField = nil
                Task { await model.checkPurchase() }
            }
            .disabled(model.isChecking)
            .accessibilityIdentifier("forecast.check")
            .clearListRow()
            if let error = model.purchaseError {
                Text(error)
                    .foregroundStyle(.red)
            }
            if let check = model.purchaseCheck {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title)
                            .font(.headline)
                        Text(check.message)
                            .font(.subheadline)
                    }
                } icon: {
                    Image(systemName: symbol(check.verdict))
                        .foregroundStyle(tint(check.verdict))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func symbol(_ verdict: PurchaseVerdict) -> String {
        switch verdict {
        case .safe: "checkmark.circle.fill"
        case .caution: "exclamationmark.circle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    private func tint(_ verdict: PurchaseVerdict) -> Color {
        switch verdict {
        case .safe: .green
        case .caution: .orange
        case .danger: .red
        }
    }
}
