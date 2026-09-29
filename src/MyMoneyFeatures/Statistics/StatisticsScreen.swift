import Charts
import Foundation
import MyMoneyDomain
import SwiftUI

/// 「統計」tab:月份、公帳代墊款與分攤建議、支出分類、收支趨勢、預算額度(parity.md「統計與預算」)。
/// 視角在 toolbar 的篩選按鈕，目前的選擇顯示在導覽列副標題。
struct StatisticsScreen: View {
    @Bindable var model: StatisticsModel
    @State private var budgetEditor: BudgetEditorModel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $model.month)
                }
                content
            }
            .skeletonTransition(value: model.phase)
            .navigationTitle("統計")
            .navigationSubtitle(model.scope.title)
            .toolbar {
                ScopeFilter("視角", scope: $model.scope, identifier: "statistics.scope")
            }
            .refreshable { await model.load() }
            // 月份、視角或資料版本任一改變就重抓。
            .task(id: QueryKey(month: model.month, scope: model.scope, version: model.dataVersion.value)) {
                await model.load()
            }
            .sheet(item: $budgetEditor) { editor in
                BudgetEditorView(model: editor)
            }
        }
    }

    private struct QueryKey: Equatable {
        let month: CalendarMonth
        let scope: ViewScope
        let version: Int
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            SkeletonSection(title: "支出分類", count: 1, announces: true) { SkeletonChart() }
            SkeletonSection(title: "收支趨勢", count: 1) { SkeletonChart(height: 160) }
            SkeletonSection(title: "預算", count: 4) { SkeletonItemRow() }
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("無法載入統計", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重試") {
                        Task { await model.load() }
                    }
                }
            }
        case .loaded:
            if model.showsHouseholdShares {
                householdSection
            }
            categorySection
            trendSection
            budgetSection
        }
    }

    private var householdSection: some View {
        Section("公帳代墊款") {
            LabeledContent("當月家庭公帳總額", value: model.householdTotal.formatted())
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("當月家庭公帳總額 \(model.householdTotal.spokenText)")
            ForEach(model.householdShares, id: \.userID) { share in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(share.userName)
                        Spacer()
                        Text(share.total.formatted())
                            .monospacedDigit()
                    }
                    ProgressView(value: fraction(share.total, of: model.householdTotal))
                    Text("佔 \(model.ratioText(share))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(share.userName),公帳代墊款 \(share.total.spokenText),佔 \(model.ratioText(share))")
            }
            if let settlement = model.settlement {
                VStack(alignment: .leading, spacing: 4) {
                    Label("分攤建議", systemImage: "lightbulb")
                        .font(.subheadline.bold())
                    Text(settlementText(settlement, spoken: false))
                        .font(.subheadline)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("分攤建議,\(settlementText(settlement, spoken: true))")
            }
        }
    }

    private func settlementText(_ settlement: Settlement, spoken: Bool) -> String {
        let text: (Money) -> String = { spoken ? $0.spokenText : $0.formatted() }
        let perPerson = "平分後每人應負擔 \(text(settlement.perPerson))"
        guard let transfer = settlement.transfer else { return "\(perPerson),兩人的公帳代墊款一樣多，不用轉帳" }
        return "\(perPerson),\(transfer.from) 轉 \(text(transfer.amount)) 給 \(transfer.to)"
    }

    private var categorySection: some View {
        Section("支出分類") {
            if model.categoryExpenses.isEmpty {
                Text("此視角本月尚無支出")
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.categoryExpenses, id: \.category) { expense in
                    SectorMark(angle: .value("金額", expense.total.chartValue), innerRadius: .ratio(0.6), angularInset: 1)
                        .foregroundStyle(by: .value("分類", expense.category.name))
                        .accessibilityLabel(expense.category.name)
                        .accessibilityValue(expense.total.spokenText)
                }
                .chartLegend(.hidden)
                .frame(height: 220)
                .padding(.vertical, 8)
                ForEach(model.categoryExpenses, id: \.category) { expense in
                    LabeledContent {
                        Text(expense.total.formatted())
                            .monospacedDigit()
                    } label: {
                        Label(expense.category.name, systemImage: expense.category.symbolName)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(expense.category.name) \(expense.total.spokenText)")
                }
                LabeledContent("合計", value: model.totalCategoryExpense.formatted())
                    .monospacedDigit()
                    .bold()
            }
        }
    }

    private var trendSection: some View {
        Section("\(String(model.month.year)) 年收支趨勢") {
            if model.monthlySummaries.isEmpty {
                Text("\(String(model.month.year)) 年尚無收支紀錄")
                    .foregroundStyle(.secondary)
            } else {
                Chart(model.monthlySummaries, id: \.month) { summary in
                    BarMark(x: .value("月份", "\(summary.month.month)月"), y: .value("金額", summary.income.chartValue))
                        .foregroundStyle(by: .value("類型", "收入"))
                        .position(by: .value("類型", "收入"))
                        .accessibilityLabel("\(summary.month.month) 月收入")
                        .accessibilityValue(summary.income.spokenText)
                    BarMark(x: .value("月份", "\(summary.month.month)月"), y: .value("金額", summary.expense.chartValue))
                        .foregroundStyle(by: .value("類型", "支出"))
                        .position(by: .value("類型", "支出"))
                        .accessibilityLabel("\(summary.month.month) 月支出")
                        .accessibilityValue(summary.expense.spokenText)
                }
                .chartForegroundStyleScale(["收入": Color.green, "支出": Color.red])
                .frame(height: 220)
                .padding(.vertical, 8)
            }
        }
    }

    private var budgetSection: some View {
        Section("預算額度") {
            ForEach(model.budgetRows) { row in
                BudgetRowView(row: row) {
                    budgetEditor = model.makeBudgetEditor(for: row)
                }
            }
        }
    }

    private func fraction(_ part: Money, of whole: Money) -> Double {
        whole > .zero ? min(part.chartValue / whole.chartValue, 1) : 0
    }
}

/// 上一個月、下一個月。
private struct MonthSwitcher: View {
    @Binding var month: CalendarMonth

    var body: some View {
        HStack {
            Button("上一個月", systemImage: "chevron.left") { month = month.previous }
                .labelStyle(.iconOnly)
            Spacer()
            Text("\(String(month.year)) 年 \(month.month) 月")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button("下一個月", systemImage: "chevron.right") { month = month.next }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
    }
}

/// 一個支出分類的已花與預算額度;超支與接近上限用 symbol 加文字，不只靠顏色。
private struct BudgetRowView: View {
    let row: BudgetRow
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(row.category.name, systemImage: row.category.symbolName)
                Spacer()
                Button(row.budget == nil ? "設定" : "調整", action: edit)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("budgets.edit.\(row.category.name)")
            }
            Text(amountText)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let budget = row.budget {
                ProgressView(value: budget.amount > .zero ? min(row.spent.chartValue / budget.amount.chartValue, 1) : 1)
                    .tint(tint)
            }
            if let statusText {
                Label(statusText, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }

    private var amountText: String {
        guard let budget = row.budget else { return "已花 \(row.spent.formatted())(未設定預算)" }
        return "已花 \(row.spent.formatted()) / 預算 \(budget.amount.formatted())"
    }

    private var statusText: String? {
        switch row.status {
        case .over(let amount): "超支 \(amount.formatted())"
        case .nearLimit: "接近上限"
        case .unset, .normal: nil
        }
    }

    private var tint: Color {
        switch row.status {
        case .over: .red
        case .nearLimit: .orange
        case .unset, .normal: .accentColor
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension BudgetEditorModel: Identifiable {}
