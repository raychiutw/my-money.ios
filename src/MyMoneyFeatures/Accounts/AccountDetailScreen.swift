import MyMoneyDomain
import SwiftUI

/// 現金與活存帳戶詳細頁:跟信用卡詳細頁同一個版型(資訊列、toolbar 的 ⋯)。動作都在 ⋯ 選單(轉帳、編輯、刪除)。
/// 資料版本改變(這一頁或其他畫面新增、修改、刪除成功)就重新取得;帳戶不見了就回到上一頁。
struct AccountDetailScreen: View {
    /// 用 `@State` 留住第一次傳入的那一份，送出中的狀態和打開的 sheet 才不會被換掉。
    @State private var model: AccountDetailModel
    @State private var editor: AccountEditorModel?
    @State private var transfer: TransferModel?
    @State private var isConfirmingDeletion = false
    @Environment(\.dismiss) private var dismiss

    init(model: AccountDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            Section("帳戶") {
                ForEach(model.rows) { row in
                    LabeledContent(row.title, value: row.value)
                }
            }
            .monospacedDigit()
            if let preview = model.debitPreview {
                Section("待扣卡費") {
                    ForEach(preview.notes, id: \.text) { note in
                        Text(note.text)
                            .foregroundStyle(note.isWarning ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                    }
                }
                .monospacedDigit()
                .accessibilityIdentifier("accountDetail.debitPreview")
            }
        }
        .navigationTitle(model.account.name)
        .inlineNavigationTitle()
        .toolbar {
            if !model.menuItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        AccountMenuButtons(items: model.menuItems, perform: perform)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("\(model.account.name)的更多動作")
                    .accessibilityIdentifier("accountDetail.more")
                }
            }
        }
        .refreshable { await model.load() }
        .task(id: model.reloadKey) { await model.refreshIfStale() }
        .onChange(of: model.isGone) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(item: $editor) { AccountEditorView(model: $0) }
        .sheet(item: $transfer) { transfer in
            TransferView(model: transfer) { message in model.noticeMessage = message }
        }
        .alert("刪除資產帳戶", isPresented: $isConfirmingDeletion) {
            Button("刪除", role: .destructive) { Task { await model.delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.deleteConfirmation)
        }
        .errorAlert("無法完成", message: model.alertMessage) { model.alertMessage = nil }
        .alert(
            "完成",
            isPresented: Binding(get: { model.noticeMessage != nil }, set: { if !$0 { model.noticeMessage = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(model.noticeMessage ?? "")
        }
    }

    private func perform(_ item: AccountMenuItem) {
        switch item {
        case .transfer: transfer = model.makeTransfer()
        case .edit: editor = model.makeEditor()
        case .delete: isConfirmingDeletion = true
        case .pay, .rollover, .reconcile: break
        }
    }
}
