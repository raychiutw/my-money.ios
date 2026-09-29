import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 週期收支：三張統計卡、週期支出與週期收入兩區(parity.md「週期收支」)。
struct RecurringScreen: View {
    @Bindable var model: RecurringModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: RecurringItem?

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("週期收支")
            .toolbar {
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
            .task(id: model.dataVersion.value) {
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
                "無法刪除",
                isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(model.alertMessage ?? "")
            }
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
                SkeletonSection(count: 3, announces: true) { SkeletonSummaryRow() }
                SkeletonSection(title: "週期支出", count: 3) { SkeletonItemRow() }
                SkeletonSection(title: "週期收入", count: 1) { SkeletonItemRow() }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入週期收支", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重試") {
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

    private var summarySection: some View {
        Section {
            SummaryRow(title: "週期支出的分攤平滑", amount: model.monthlyExpense)
            SummaryRow(title: "週期收入的分攤平滑", amount: model.monthlyIncome)
            SummaryRow(title: "每月固定淨額", amount: model.monthlyNet, warnsWhenNegative: true)
        }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認)。
    private func row(_ item: RecurringItem) -> some View {
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
    }
}

/// 一項週期收支：名稱、扣款日或入帳日、關聯帳戶、(非每月的週期支出)分攤平滑、每期金額。
private struct RecurringRow: View {
    let item: RecurringItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                Text(item.scheduleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                // 金額一律帶正負號，收入綠色、支出紅色(DESIGN.md「顏色」)。
                Text(item.type == .income ? "+\(item.amount.formatted())" : "-\(item.amount.formatted())")
                    .monospacedDigit()
                    .foregroundStyle(item.type == .income ? .green : .red)
                Text("\(item.cycle.label)\(item.type == .income ? "收" : "繳")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.name),\(item.type == .income ? "週期收入" : "週期支出") \(item.amount.spokenText),\(item.scheduleText),"
                + details(spoken: true)
        )
    }

    private var details: String { details(spoken: false) }

    private func details(spoken: Bool) -> String {
        let account = item.accountName.map { item.type == .income ? "入帳帳戶：\($0)" : "關聯扣款帳戶：\($0)" } ?? "未指定關聯帳戶"
        guard item.showsMonthlyAmortization else { return account }
        let amortization = spoken ? item.monthlyAmortization.spokenText : item.monthlyAmortization.formatted()
        return "\(account) · 分攤平滑 \(amortization) / 月"
    }
}
