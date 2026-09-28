import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 固定收支：三張統計卡、固定支出與固定收入兩區(parity.md「固定收支」)。
struct RecurringScreen: View {
    @Bindable var model: RecurringModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: RecurringItem?

    var body: some View {
        content
            .navigationTitle("固定收支")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = EditorSheet(model.makeEditor())
                    } label: {
                        Label("新增固定收支", systemImage: "plus")
                    }
                    .accessibilityIdentifier("recurring.add")
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(
                        item: model.csvExport(),
                        preview: SharePreview("固定收支 CSV", image: Image(systemName: "tablecells"))
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
                "刪除固定收支",
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入固定收支", systemImage: "exclamationmark.triangle")
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
                Section("固定支出(\(model.expenses.count))") {
                    if model.expenses.isEmpty {
                        Text("尚未新增固定支出")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.expenses) { item in
                        row(item)
                    }
                }
                Section("固定收入(\(model.incomes.count))") {
                    if model.incomes.isEmpty {
                        Text("尚未設定固定收入")
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
            SummaryRow(title: "固定支出的週期攤提", amount: model.monthlyExpense, detail: "年繳、季繳換算成每月要預留的金額")
            SummaryRow(title: "固定收入的週期攤提", amount: model.monthlyIncome, detail: "每月穩定入帳的金額")
            SummaryRow(title: "每月固定淨額", amount: model.monthlyNet, detail: "固定收入減固定支出", warnsWhenNegative: true)
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

/// 一項固定收支：名稱、扣款日或入帳日、關聯帳戶、(非每月的固定支出)週期攤提、每期金額。
private struct RecurringRow: View {
    let item: RecurringItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                Text(item.scheduleText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                // 金額一律帶正負號，收入綠色、支出紅色(DESIGN.md「顏色」)。
                Text(item.type == .income ? "+\(item.amount.formatted())" : "-\(item.amount.formatted())")
                    .monospacedDigit()
                    .foregroundStyle(item.type == .income ? .green : .red)
                Text("\(item.cycle.label)\(item.type == .income ? "收" : "繳")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.name),\(item.type == .income ? "固定收入" : "固定支出") \(item.amount.spokenText),\(item.scheduleText),"
                + details(spoken: true)
        )
    }

    private var details: String { details(spoken: false) }

    private func details(spoken: Bool) -> String {
        let account = item.accountName.map { item.type == .income ? "入帳帳戶：\($0)" : "關聯扣款帳戶：\($0)" } ?? "未指定關聯帳戶"
        guard item.showsMonthlyAmortization else { return account }
        let amortization = spoken ? item.monthlyAmortization.spokenText : item.monthlyAmortization.formatted()
        return "\(account) · 週期攤提 \(amortization) / 月"
    }
}
