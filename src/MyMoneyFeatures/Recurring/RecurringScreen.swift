import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 週期收支：摘要(一個主數字加一般列)、週期支出與週期收入兩區(parity.md「週期收支」)。
struct RecurringScreen: View {
    @Bindable var model: RecurringModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: RecurringItem?
    /// 點了點不開的項目:跳出簡短說明。
    @State private var explained: RecurringItem?

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("週期收支")
            .navigationSubtitle(model.scope.title)
            .toolbar {
                ScopeFilter("視角", scope: $model.scope, identifier: "recurring.scope")
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = EditorSheet(model.makeEditor())
                    } label: {
                        Label("新增週期收支", systemImage: "plus")
                    }
                    .accessibilityIdentifier("recurring.add")
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(
                        item: model.csvExport(),
                        preview: SharePreview("週期收支 CSV", image: Image(systemName: "tablecells"))
                    ) {
                        Label("匯出 CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
            // 視角或資料版本改變就重抓。
            .task(id: QueryKey(scope: model.scope, version: model.dataVersion.value)) {
                await model.refreshIfStale()
            }
            .sheet(item: $editor) { sheet in
                RecurringEditorView(model: sheet.model)
            }
            .confirmationDialog(
                "刪除週期收支",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { item in
                Button("刪除", role: .destructive) {
                    Task { await model.delete(item) }
                }
                Button("取消", role: .cancel) {}
            } message: { item in
                Text(model.deleteConfirmation(for: item))
            }
            .alert(
                model.lockAlertTitle,
                isPresented: Binding(get: { explained != nil }, set: { if !$0 { explained = nil } }),
                presenting: explained
            ) { _ in
                Button("好") {}
            } message: { item in
                Text("\(model.lockReason(for: item) ?? "")。")
            }
            .alert(
                "無法刪除",
                isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(model.alertMessage ?? "")
            }
    }

    private struct QueryKey: Hashable {
        let scope: ViewScope
        let version: Int
    }

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: RecurringEditorModel

        init(_ model: RecurringEditorModel) {
            self.model = model
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                Section {
                    SummaryRow(title: Terms.expenseAmortization, amount: Skeleton.amount)
                        .skeletonAnnouncement()
                    ForEach(0..<2, id: \.self) { _ in
                        AmountRow(title: "摘要數字", amount: Skeleton.amount)
                            .skeletonRow()
                    }
                }
                SkeletonSection(title: "週期支出", count: 3) { SkeletonItemRow() }
                SkeletonSection(title: "週期收入", count: 1) { SkeletonItemRow() }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入週期收支", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                GlassCapsuleButton(title: "重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            List {
                summarySection
                Section("週期支出(\(model.expenses.count))") {
                    if model.expenses.isEmpty {
                        Text("尚未新增週期支出")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.expenses) { item in
                        row(item)
                    }
                }
                Section("週期收入(\(model.incomes.count))") {
                    if model.incomes.isEmpty {
                        Text("尚未設定週期收入")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.incomes) { item in
                        row(item)
                    }
                }
            }
            .refreshable { await model.load() }
        }
    }

    /// 摘要：週期支出每月平均是主數字，其餘是一般列(DESIGN.md「列與欄位」第 6 條，#77)。
    private var summarySection: some View {
        Section {
            SummaryRow(title: Terms.expenseAmortization, amount: model.monthlyExpense)
            AmountRow(title: Terms.incomeAmortization, amount: model.monthlyIncome)
            AmountRow(title: "每月週期淨額", amount: model.monthlyNet, warnsWhenNegative: true)
        }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認)。不能改的項目(他人建立的家庭公帳，自己不是家庭管理員)
    /// 點一下跳出說明,沒有左滑刪除與長按選單(上游 ADR 0016)。
    @ViewBuilder
    private func row(_ item: RecurringItem) -> some View {
        if model.canModify(item) {
            Button {
                editor = EditorSheet(model.makeEditor(editing: item))
            } label: {
                RecurringRow(item: item)
            }
            .tint(.primary)
            .swipeActions {
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = item
                }
            }
            .contextMenu {
                Button("編輯", systemImage: "pencil") {
                    editor = EditorSheet(model.makeEditor(editing: item))
                }
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = item
                }
            }
        } else {
            Button {
                explained = item
            } label: {
                RecurringRow(item: item, lockHint: model.lockHint(for: item))
            }
            .tint(.primary)
        }
    }
}

/// 一項週期收支，一行一個欄位(DESIGN.md「列與欄位」,#77):
///
/// - 第 1 行：名稱。
/// - 第 2 行：週期與日期，例如「每月 5 號扣款」。
/// - 第 3 行：「建立者・歸屬」，例如「小美・家庭公帳」;自己建立的也顯示。
/// - 第 4 行：資產帳戶名稱，不加前綴;沒設就不顯示。
/// - trailing:帶正負號的每期金額，下面是非每月週期支出的每月分攤平滑，例如「$2,000／月」。
///
/// 放不下時(大字級)改成上下堆疊，金額一律單行。VoiceOver 把整列念成一句。
private struct RecurringRow: View {
    let item: RecurringItem
    /// 點不開的項目的 VoiceOver 提示(「點兩下查看為什麼不能編輯」)。
    var lockHint: String?

    /// 左右並列時，文字欄至少要有的寬度，跟著字級變大;放不下就改成上下堆疊(同 `TransactionRow`)。
    @ScaledMetric(relativeTo: .body) private var minimumTextWidth: CGFloat = 120

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                texts
                    .frame(minWidth: minimumTextWidth, idealWidth: minimumTextWidth, maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    amountText
                    amortization
                }
            }
            // 堆疊時(無障礙字級):分攤平滑在上、金額在最下面一行，都靠右(#149)。
            VStack(alignment: .leading, spacing: 4) {
                texts
                VStack(alignment: .trailing, spacing: 4) {
                    amortization
                    amountText
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spokenText)
        .accessibilityHint(lockHint ?? "")
    }

    @ViewBuilder
    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            Text(item.scheduleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // 建立者・歸屬:自己建立的也顯示(上游 ADR 0016)。
            Text(item.ownerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let account = item.accountText {
                Text(account)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amountText: some View {
        // 金額一律帶正負號，收入綠色、支出紅色(DESIGN.md「顏色」)。
        Text(item.type == .income ? "+\(item.amount.formatted())" : "-\(item.amount.formatted())")
            .monospacedDigit()
            .foregroundStyle(item.type == .income ? .green : .red)
            .lineLimit(1)
            .fixedSize()
    }

    /// 非每月週期支出的每月分攤平滑，例如「$2,000／月」。
    @ViewBuilder
    private var amortization: some View {
        if let amortization = item.amortizationText {
            Text(amortization)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
