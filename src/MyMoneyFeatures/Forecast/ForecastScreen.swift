import Charts
import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 現金流預測：透支風險、最低餘額、預定收支、30 天逐日餘額與購買力試算(parity.md「現金流預測」)。
struct ForecastScreen: View {
    @Bindable var model: ForecastModel
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Field {
        case amount
    }

    private struct QueryKey: Hashable {
        let scope: ViewScope
        let version: Int
    }

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("現金流預測")
            .navigationSubtitle(model.scope.title)
            .toolbar {
                ScopeFilter("視角", scope: $model.scope, identifier: "forecast.scope")
            }
            // 視角或資料版本改變就重抓。
            .task(id: QueryKey(scope: model.scope, version: model.dataVersion.value)) {
                await model.refreshIfStale()
            }
            .keyboardDismissal(clearing: $focusedField)
            .alert(
                "無法更新已繳狀態",
                isPresented: Binding(get: { model.settleError != nil }, set: { if !$0 { model.clearSettleError() } })
            ) {
                Button("好") {}
            } message: {
                Text(model.settleError ?? "")
            }
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
                        Text("預計餘額會跌破 0，請及早調整")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: forecast.willOverdraft ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(forecast.willOverdraft ? .red : .green)
            }
            .accessibilityElement(children: .combine)
            if let start = model.startingBalance(of: forecast) {
                VStack(alignment: .leading, spacing: 4) {
                    AmountRow(title: "起始餘額", amount: start.amount)
                    Text(start.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let note = start.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("起始餘額")
                .accessibilityValue(([start.amount.spokenText, start.detail] + [start.note].compactMap { $0 }).joined(separator: ","))
                .accessibilityIdentifier("forecast.startingBalance")
            }
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
            // 日期刻度的字照系統字級放大，放不下就少放幾個刻度，不讓標籤被截成「10月1…」(#157)。
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: axisLabelCount)) { value in
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

    /// x 軸的日期刻度數;預設字級交給系統決定。XXL 以上最多放 2 個(3 個時兩位數的日期,例如「10月19日」「10月26日」,
    /// 會被截成「10月1…」;一位數的日期較窄,所以只在月初幾天才碰巧放得下，測試因此隨日期忽過忽不過)。
    private var axisLabelCount: Int? {
        dynamicTypeSize >= .xxLarge ? 2 : nil
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
                HStack(alignment: .top, spacing: 4) {
                    ForecastEventRow(
                        event: event, subtitle: model.subtitle(of: event), account: model.accountText(of: event),
                        settledNote: model.settledNote(of: event), spokenText: model.spokenText(of: event)
                    )
                    if let key = event.key, event.canSettle {
                        SettleButton(isSettled: event.isSettled, isBusy: model.settlingKeys.contains(key)) {
                            Task { await model.setSettled(!event.isSettled, for: event) }
                        }
                        .accessibilityIdentifier("forecast.settle.\(key)")
                    }
                }
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
            .tapToFocus($focusedField, equals: .amount)
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

/// 一筆預定收支(#155)：跟交易列同一種讀法——左邊名稱加「日期・歸屬」，右邊帶正負號的金額，金額下面是資產帳戶名稱
/// (靠右、單行、太長從結尾截斷)。無障礙字級上下堆疊:名稱、日期・歸屬、資產帳戶，**金額在最下面一行、靠右**。
private struct ForecastEventRow: View {
    let event: ForecastEvent
    let subtitle: String
    let account: String?
    /// 已繳的事件多一行說明「已繳(不計入預測)」，不只靠變淡與刪除線(#182)。
    let settledNote: String?
    let spokenText: String

    @ScaledMetric(relativeTo: .subheadline) private var accountMaxWidth: CGFloat = 120
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name)
                    subtitleText
                    settledText
                    accountText
                    amount
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name)
                        subtitleText
                        settledText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        amount
                        accountText
                    }
                }
            }
        }
        // 已繳:整列變淡(不計入預測)，金額加刪除線。
        .opacity(event.isSettled ? 0.58 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    @ViewBuilder
    private var settledText: some View {
        if let settledNote {
            Text(settledNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    @ViewBuilder
    private var accountText: some View {
        if let account {
            Text(account)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // 無障礙字級折行、不截斷;其他字級單行、太長從結尾截斷。
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : accountMaxWidth,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
        }
    }

    /// 金額一律單行，帶正負號(收入綠、支出紅)。
    private var amount: some View {
        Text(event.amount.formatted(flow: event.type == .income ? .inflow : .outflow))
            .monospacedDigit()
            .foregroundStyle(event.amount.tone(of: event.type == .income ? .inflow : .outflow).color ?? .primary)
            .strikethrough(event.isSettled)
            .lineLimit(1)
            .fixedSize()
    }
}

/// 預定收支右邊的「已繳」圓圈(上游 ADR 0018，#182):未繳是空心圓、已繳是 CI 填色加勾勾;觸控範圍 44×44pt，
/// VoiceOver 念「標示為已繳」或「取消已繳」。送出期間停用。預測頁與總覽「接下來 30 天」共用。
struct SettleButton: View {
    let isSettled: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSettled ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSettled ? Color.ciFill : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(isSettled ? "取消已繳" : "標示為已繳")
    }
}
