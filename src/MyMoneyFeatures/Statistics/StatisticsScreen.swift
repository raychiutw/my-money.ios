import Charts
import Foundation
import MyMoneyDomain
import SwiftUI

/// 「統計」tab:數字優先(#120):精簡的月份列、超大的當月支出、公帳代墊款與分攤建議、支出分類環圈、
/// 12 個月收支趨勢、預算額度(parity.md「統計與預算」)。
/// 視角在 toolbar 的篩選按鈕，目前的選擇由按鈕的圖示狀態表達。
struct StatisticsScreen: View {
    @Bindable var model: StatisticsModel
    @State private var budgetEditor: BudgetEditorModel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSwitcher(month: $model.month, title: model.monthTitle)
                        .clearListRow()
                }
                .compactSectionSpacing()
                content
            }
            .skeletonTransition(value: model.phase)
            .tabRootNavigation("統計")
            .toolbar {
                ScopeFilter("視角", scope: $model.scope, identifier: "statistics.scope")
                AccountToolbarItem()
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
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    BigNumber(title: "支出", amount: Skeleton.amount)
                }
                .padding(.vertical, 8)
                .skeletonAnnouncement()
            }
            SkeletonSection(title: "支出分類", count: 1) { SkeletonChart() }
            SkeletonSection(title: "收支趨勢", count: 1) { SkeletonChart(height: 160) }
            SkeletonSection(title: "預算額度", count: 4) { SkeletonItemRow() }
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
            Section {
                BigNumber(title: model.expenseTitle, amount: model.totalCategoryExpense, warnsWhenNegative: false)
                    .padding(.vertical, 8)
            }
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
                settlementView(settlement)
            }
        }
    }

    /// 分攤建議以數字為主(#120):轉帳金額是大數字，「誰轉給誰」在上面，平分後每人負擔在下面;
    /// 兩人的公帳代墊款一樣多時只有一句「不用轉帳」。VoiceOver 念完整的一句(跟以前一樣)。
    private func settlementView(_ settlement: Settlement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("分攤建議", systemImage: "lightbulb")
                .font(.subheadline.bold())
            if let transfer = settlement.transfer {
                Text("\(transfer.from) 轉給 \(transfer.to)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(transfer.amount.formatted())
                    .font(.title.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("平分後每人負擔 \(settlement.perPerson.formatted())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("兩人的公帳代墊款一樣多，不用轉帳")
                    .font(.subheadline)
                Text("平分後每人負擔 \(settlement.perPerson.formatted())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("分攤建議,\(settlementText(settlement, spoken: true))")
    }

    private func settlementText(_ settlement: Settlement, spoken: Bool) -> String {
        let text: (Money) -> String = { spoken ? $0.spokenText : $0.formatted() }
        let perPerson = "平分後每人應負擔 \(text(settlement.perPerson))"
        guard let transfer = settlement.transfer else { return "\(perPerson),兩人的公帳代墊款一樣多，不用轉帳" }
        return "\(perPerson),\(transfer.from) 轉 \(text(transfer.amount)) 給 \(transfer.to)"
    }

    /// 圓餅圖最多 8 塊:金額最大的幾種用各自固定的顏色，其餘(含沒有專屬色的分類)併成 1 塊灰色(`ExpenseChart`,#100)。
    /// 下方清單列出全部分類，每列前緣的圓點顏色跟圖一致(合併進灰色的，圓點也是灰色)，當圖例用;
    /// 分類名稱照舊顯示，不只靠顏色(研究 §10,#76)。
    private var categorySection: some View {
        let chart = model.expenseChart
        return Section("支出分類") {
            if model.categoryExpenses.isEmpty {
                Text("此視角本月尚無支出")
                    .foregroundStyle(.secondary)
            } else {
                Chart(chart.slices) { slice in
                    SectorMark(angle: .value("金額", slice.total.chartValue), innerRadius: .ratio(0.6), angularInset: 1)
                        .foregroundStyle(by: .value("分類", slice.name))
                        .accessibilityLabel(slice.spokenName)
                        .accessibilityValue(slice.total.spokenText)
                }
                .chartForegroundStyleScale(
                    domain: chart.slices.map(\.name),
                    range: chart.slices.map(\.color.color)
                )
                .chartLegend(.hidden)
                .frame(height: 200)
                .padding(.vertical, 8)
                ForEach(model.categoryExpenses, id: \.category) { expense in
                    LabeledContent {
                        Text(expense.total.formatted())
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text(expense.category.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .imageScale(.small)
                                .foregroundStyle(chart.color(for: expense.category).color)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(expense.category.name) \(expense.total.spokenText)")
                }
            }
        }
    }

    private var trendSection: some View {
        Section("\(model.yearTitle)收支趨勢") {
            if model.monthlySummaries.isEmpty {
                Text("\(model.yearTitle)尚無收支紀錄")
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
                .frame(height: 180)
                .padding(.vertical, 8)
            }
        }
    }

    /// 只列有預算或本月已花的分類，整列點開設定 sheet;其餘分類由底部的「新增預算額度」直接打開同一個 sheet,
    /// 分類在 sheet 裡用分類格選(不再先列出最多 15 項的選單);全部都列出時不顯示。
    private var budgetSection: some View {
        Section("預算額度") {
            ForEach(model.budgetRows) { row in
                Button {
                    budgetEditor = model.makeBudgetEditor(for: row.category)
                } label: {
                    BudgetRowView(row: row)
                }
                .tint(.primary)
                .accessibilityLabel(row.spokenText)
                .accessibilityIdentifier("budgets.row.\(row.category.name)")
            }
            // 直接打開編輯，不再先列出最多 15 項的選單;分類在編輯裡用分類格選(ADR-0004、#101)。
            if model.makeNewBudgetEditor() != nil {
                Button {
                    budgetEditor = model.makeNewBudgetEditor()
                } label: {
                    AddBudgetLabel()
                }
                .accessibilityIdentifier("budgets.add")
            }
        }
    }

    private func fraction(_ part: Money, of whole: Money) -> Double {
        whole > .zero ? min(part.chartValue / whole.chartValue, 1) : 0
    }
}

/// 精簡的月份列(#120):上一個月、所選的月份、下一個月，不是卡片也不佔標題位置;兩個按鈕的觸控範圍至少 44×44pt。
private struct MonthSwitcher: View {
    @Binding var month: CalendarMonth
    /// 所選的月份(畫面 model 依系統格式產生)。
    let title: String

    var body: some View {
        HStack {
            Button("上一個月", systemImage: "chevron.left") { month = month.previous }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            Spacer()
            Text(title)
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button("下一個月", systemImage: "chevron.right") { month = month.next }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
    }
}

/// 「新增預算額度」的 label:整列都點得開，不只文字的範圍。
///
/// 不用 `Label`:AX5 字級折成兩行會被裁掉、圖示壓到文字(#76 的截圖),
/// 改成自己排圖示和文字。圖示欄的寬度和間距跟 List 裡的 `Label` 差不多，文字對齊上面各列的分類名稱。
private struct AddBudgetLabel: View {
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "plus")
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text("新增預算額度")
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// 預算額度的一列(#76、#120,DESIGN.md「列與欄位」):分類名稱與「已花 / 預算」一行，沒有預算時是「已花 / 未設定」;
/// 有預算時下面是進度條，超支紅色、接近上限橙色，並有警示圖示加文字，不只靠顏色。
/// 整列是按鈕，VoiceOver 念 `spokenText`。大字級放不下時名稱與數字改成上下堆疊，數字一律單行。
private struct BudgetRowView: View {
    let row: BudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(row.category.name, systemImage: row.category.symbolName)
                    Spacer(minLength: 8)
                    figures
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(row.category.name, systemImage: row.category.symbolName)
                    figures
                }
            }
            if let budget = row.budget {
                // 超支時進度卡在 100%,VoiceOver 改念 `spokenText` 裡的超支金額。
                ProgressView(value: budget.amount > .zero ? min(row.spent.chartValue / budget.amount.chartValue, 1) : 1)
                    .tint(tint)
                    .accessibilityHidden(true)
            }
            if let statusText = row.statusText(spoken: false) {
                Label(statusText, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }

    /// 「已花 / 預算」:已花是主要數字，預算(或「未設定」)是次要色。金額一律單行(DESIGN.md「列與欄位」)。
    private var figures: some View {
        HStack(spacing: 4) {
            Text(row.spent.formatted())
                .foregroundStyle(row.status.isOver ? Color.red : .primary)
            Text("/")
                .foregroundStyle(.secondary)
            Text(row.budget.map { $0.amount.formatted() } ?? "未設定")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    private var tint: Color {
        switch row.status {
        case .over: .red
        case .nearLimit: .orange
        case .unset, .normal: .accentColor
        }
    }
}

extension BudgetRow.Status {
    fileprivate var isOver: Bool {
        if case .over = self { true } else { false }
    }
}

extension BudgetRow {
    /// 例如「餐飲，預算 100 元，已花 120 元，超支 20 元」「交通，預算未設定，已花 250 元」。
    fileprivate var spokenText: String {
        var parts = [
            category.name,
            budget.map { "預算 \($0.amount.spokenText)" } ?? "預算未設定",
            "已花 \(spent.spokenText)",
        ]
        if let status = statusText(spoken: true) { parts.append(status) }
        return parts.joined(separator: "，")
    }

    fileprivate func statusText(spoken: Bool) -> String? {
        switch status {
        case .over(let amount): "超支 \(spoken ? amount.spokenText : amount.formatted())"
        case .nearLimit: "接近上限"
        case .unset, .normal: nil
        }
    }
}

extension CategoryChartColor {
    /// 系統色，深色和增強對比由系統調整(DESIGN.md「顏色」)。
    fileprivate var color: Color {
        switch self {
        case .orange: .orange
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .cyan: .cyan
        case .yellow: .yellow
        case .indigo: .indigo
        case .teal: .teal
        case .mint: .mint
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension BudgetEditorModel: Identifiable {}
