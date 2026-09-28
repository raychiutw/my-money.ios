import Charts
import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 現金流預測：透支風險、最低餘額、預定收支、30 天逐日餘額與購買力試算(parity.md「現金流預測」)。
struct ForecastScreen: View {
    @Bindable var model: ForecastModel
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        content
            .navigationTitle("現金流預測")
            .task(id: model.dataVersion.value) {
                await model.refreshIfStale()
            }
            .keyboardDoneButton { isAmountFocused = false }
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
                Button("重試") {
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
            // 資料回來之前不顯示「安全」或 $0(parity 刻意偏離第 7 項)。
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summarySection(_ forecast: CashFlowForecast) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(forecast.riskTitle)
                        .font(.headline)
                    Text(forecast.willOverdraft ? "預計餘額會跌破 0,請及早調整" : "排定的收支都發生後，餘額仍然大於 0")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: forecast.willOverdraft ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(forecast.willOverdraft ? .red : .green)
            }
            .accessibilityElement(children: .combine)
            SummaryRow(
                title: "最低餘額",
                amount: forecast.minBalance,
                detail: forecast.minDate == nil ? forecast.minDateText : "發生在 \(forecast.minDateText)",
                warnsWhenNegative: true
            )
            LabeledContent("未來 30 天的預定收支", value: "\(forecast.events.count) 筆")
        }
    }

    private func chartSection(_ forecast: CashFlowForecast) -> some View {
        Section {
            Chart(forecast.dailyBalances, id: \.date) { day in
                AreaMark(x: .value("日期", day.date.startOfDay), y: .value("餘額", day.balance.chartValue))
                    .foregroundStyle(.tint.opacity(0.2))
                    .accessibilityHidden(true)
                LineMark(x: .value("日期", day.date.startOfDay), y: .value("餘額", day.balance.chartValue))
                    .accessibilityLabel("\(day.date.month) 月 \(day.date.day) 日")
                    .accessibilityValue("餘額 \(day.balance.spokenText)")
                if forecast.willOverdraft {
                    RuleMark(y: .value("零", 0))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 220)
            .padding(.vertical, 8)
        } header: {
            Text("未來 30 天逐日餘額")
        } footer: {
            Text("起始餘額是自己的銀行存款帳戶餘額合計，扣掉自己信用卡的待繳卡費總額;不含現金錢包，也不含其他家庭成員的資金帳戶。")
        }
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
                        Text(event.date.slashText)
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
                    "\(event.name),\(event.date.month) 月 \(event.date.day) 日,\(event.type == .income ? "收入" : "支出") \(event.amount.spokenText)"
                )
            }
        }
    }

    private var purchaseSection: some View {
        Section {
            LabeledContent("購買金額") {
                AmountField(
                    "購買金額", text: $model.purchaseAmountText, prompt: Text("例如：25000"),
                    focus: $isAmountFocused, equals: true, identifier: "forecast.purchaseAmount"
                )
            }
            Button("進行購買力試算") {
                isAmountFocused = false
                Task { await model.checkPurchase() }
            }
            .disabled(model.isChecking)
            .accessibilityIdentifier("forecast.check")
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
        } header: {
            Text("購買力試算")
        } footer: {
            Text("輸入打算花的金額，看它對未來 30 天現金流和儲蓄目標的影響。")
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
