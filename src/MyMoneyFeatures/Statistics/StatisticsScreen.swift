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
                    MonthSwitcher(month: $model.month, title: model.monthTitle)
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

    /// 圓餅圖和下方清單共用同一份「分類 → 顏色」對照(`chartColor`),清單每列前緣的圓點就是圖例;
    /// 分類名稱照舊顯示，不只靠顏色(研究 §10,#76)。
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
                .chartForegroundStyleScale(
                    domain: model.categoryExpenses.map(\.category.name),
                    range: model.categoryExpenses.map(\.category.chartColor)
                )
                .chartLegend(.hidden)
                .frame(height: 220)
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
                                .foregroundStyle(expense.category.chartColor)
                        }
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
                .frame(height: 220)
                .padding(.vertical, 8)
            }
        }
    }

    /// 只列有預算或本月已花的分類，整列點開設定 sheet;其餘分類在底部的「新增預算額度」選單，
    /// 選了打開同一個 sheet,全部都列出時不顯示(HIG Pull-down buttons 的「An Add button could present a menu」,
    /// 研究 §5,#76)。
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
            if !model.addableBudgetCategories.isEmpty {
                Menu {
                    ForEach(model.addableBudgetCategories, id: \.self) { category in
                        Button(category.name, systemImage: category.symbolName) {
                            budgetEditor = model.makeBudgetEditor(for: category)
                        }
                    }
                } label: {
                    AddBudgetMenuLabel()
                }
                .accessibilityIdentifier("budgets.add")
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
    /// 所選的月份(畫面 model 依系統格式產生)。
    let title: String

    var body: some View {
        HStack {
            Button("上一個月", systemImage: "chevron.left") { month = month.previous }
                .labelStyle(.iconOnly)
            Spacer()
            Text(title)
                .font(.headline)
                .monospacedDigit()
            Spacer()
            Button("下一個月", systemImage: "chevron.right") { month = month.next }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
    }
}

/// 「新增預算額度」選單的 label:整列都點得開，不只文字的範圍。
///
/// 不用 `Label`:`Menu` 的 label 是 `Label` 時，AX5 字級折成兩行會被裁掉、圖示壓到文字(#76 的截圖),
/// 改成自己排圖示和文字。圖示欄的寬度和間距跟 List 裡的 `Label` 差不多，文字對齊上面各列的分類名稱。
private struct AddBudgetMenuLabel: View {
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

/// 預算額度的一列(#76,DESIGN.md「列與欄位」):分類;已花、預算各一列(沒有預算時是「未設定」);
/// 有預算時是進度;超支與接近上限用 symbol 加文字，不只靠顏色。整列是按鈕，VoiceOver 念 `spokenText`。
private struct BudgetRowView: View {
    let row: BudgetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(row.category.name, systemImage: row.category.symbolName)
            field("已花", value: row.spent.formatted())
            if let budget = row.budget {
                field("預算", value: budget.amount.formatted())
                // 超支時進度卡在 100%,VoiceOver 改念 `spokenText` 裡的超支金額。
                ProgressView(value: budget.amount > .zero ? min(row.spent.chartValue / budget.amount.chartValue, 1) : 1)
                    .tint(tint)
                    .accessibilityHidden(true)
            } else {
                field("預算", value: "未設定", isPlaceholder: true)
            }
            if let statusText = row.statusText(spoken: false) {
                Label(statusText, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }

    /// 已花、預算各一列：標籤在左、金額在右，大字級放不下時自動上下堆疊，金額一律單行(DESIGN.md「列與欄位」)。
    /// 字級直接設在 `Text` 上：設在外層時，List 裡的 `LabeledContent` 仍是 `body`(#76 的截圖)。
    /// `isPlaceholder`:沒有值(「未設定」)時用次要文字色，跟金額區分。
    private func field(_ title: String, value: String, isPlaceholder: Bool = false) -> some View {
        LabeledContent {
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize()
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

extension TransactionCategory {
    /// 支出分類圖表的顏色：圓餅圖和清單的圓點共用，跟著分類固定，不隨排序或月份改變(DESIGN.md「顏色」)。
    /// 用系統色，深色和增強對比由系統調整。挑的 8 色在淺色、深色下任兩色都分得開(一般色覺 OKLab ΔE ≥ 15);
    /// 紅色留給支出和超支，不用。
    /// 「其他」和不在清單中的分類(例如機器人記帳寫入的)是灰色。
    fileprivate var chartColor: Color {
        switch name {
        case "餐飲": .orange
        case "交通": .blue
        case "娛樂": .purple
        case "購物": .pink
        case "生活": .green
        case "醫療": .cyan
        case "教育": .yellow
        default: .gray
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension BudgetEditorModel: Identifiable {}
