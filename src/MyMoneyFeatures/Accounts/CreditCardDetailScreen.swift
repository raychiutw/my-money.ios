import MyMoneyDomain
import SwiftUI

/// 信用卡詳細頁(#73,DESIGN.md「導覽」):從帳戶頁或總覽的信用卡精簡列 push 進來。
///
/// 每個欄位一列(`LabeledContent`):「卡費」「設定」兩區。動作都在 toolbar 的 ⋯ 選單:繳款(沒有對應欠款的項目隱藏)、
/// 出帳作業、校準未出帳、編輯、刪除。繳款、出帳作業、校準、編輯成功後資料版本遞增，這一頁重新取得。
struct CreditCardDetailScreen: View {
    /// 由路由(`navigationDestination`)建立後傳入。父層重畫時路由會再建立一份新的 model,
    /// 用 `@State` 留住第一次傳入的那一份，送出中的狀態和打開的 sheet 才不會被換掉。
    @State private var model: CreditCardDetailModel
    @State private var payment: CardPaymentModel?
    @State private var editor: AccountEditorModel?
    @State private var rollover: StatementRolloverModel?
    @State private var isAskingForStatementDay = false
    @State private var isConfirmingReconcile = false
    @State private var isConfirmingDeletion = false
    @Environment(\.dismiss) private var dismiss

    init(model: CreditCardDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            feesSection
            settingsSection
        }
        .navigationTitle(model.card.name)
        .inlineNavigationTitle()
        .toolbar {
            // 個人信用卡只有持卡人能出帳、校準、繳個人私帳(上游 ADR 0013、#133);他人的卡只能繳家庭代墊(ADR 0015、#140);
            // 沒有任何可做的動作就不顯示 ⋯。
            if !model.menuItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        AccountMenuButtons(items: model.menuItems, isReconciling: model.isReconciling, perform: perform)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("\(model.card.name)的更多動作")
                    .accessibilityIdentifier("cardDetail.more")
                }
            }
        }
        .refreshable { await model.load() }
        // 資料版本改變(這一頁或其他畫面新增、修改、刪除成功)就重新取得。
        .task(id: model.reloadKey) {
            await model.refreshIfStale()
        }
        // 這張卡已經不在這個帳戶檢視範圍(被刪除，或歸屬改了):回到上一頁。
        .onChange(of: model.isGone) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(item: $payment) { payment in
            CardPaymentView(model: payment)
        }
        .sheet(item: $editor) { editor in
            AccountEditorView(model: editor)
        }
        .sheet(item: $rollover) { rollover in
            StatementRolloverView(model: rollover) { message in model.noticeMessage = message }
        }
        .alert("校準未出帳", isPresented: $isConfirmingReconcile) {
            Button("校準") { Task { await model.reconcile() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.reconcileConfirmation)
        }
        .alert("刪除資產帳戶", isPresented: $isConfirmingDeletion) {
            Button("刪除", role: .destructive) { Task { await model.delete() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.deleteConfirmation)
        }
        .alert("無法出帳作業", isPresented: $isAskingForStatementDay) {
            Button("前往設定") { editor = model.makeEditor() }
                .accessibilityIdentifier("cardDetail.setStatementDay")
            Button("取消", role: .cancel) {}
        } message: {
            Text(StatementRolloverModel.missingStatementDayMessage)
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

    private var card: CreditCard { model.card }

    private var feesSection: some View {
        Section("卡費") {
            ForEach(model.feeRows) { row in
                LabeledContent(row.title, value: row.value)
            }
        }
        .monospacedDigit()
    }

    private var settingsSection: some View {
        Section("設定") {
            ForEach(model.limitRows) { row in
                LabeledContent(row.title, value: row.value)
            }
            LabeledContent("結帳日", value: Self.monthlyDay(card.statementDay))
            LabeledContent("繳款日", value: Self.monthlyDay(card.paymentDueDay))
            if let row = model.paymentAccountRow {
                LabeledContent(row.title, value: row.value)
                    .accessibilityIdentifier("cardDetail.paymentAccount")
            }
        }
        .monospacedDigit()
    }

    /// 例如「每月 15 日」;沒有設定時是「未設定」。
    private static func monthlyDay(_ day: Int?) -> String {
        day.map { "每月 \($0) 日" } ?? "未設定"
    }

    /// ⋯ 選單的每個項目要做的事。
    private func perform(_ item: AccountMenuItem) {
        switch item {
        case .pay(let preset):
            payment = model.makePayment(preset)
        case .rollover:
            if model.rolloverNeedsStatementDay {
                isAskingForStatementDay = true
            } else {
                rollover = model.makeStatementRollover()
            }
        case .reconcile:
            isConfirmingReconcile = true
        case .edit:
            editor = model.makeEditor()
        case .delete:
            isConfirmingDeletion = true
        case .transfer:
            break
        }
    }
}

extension CardPaymentModel.Preset {
    /// ⋯ 選單的繳款項目。
    var title: String {
        switch self {
        case .shared: "繳家庭代墊"
        case .personal: "繳個人私帳"
        case .full: "全額結清"
        }
    }

    var systemImage: String {
        switch self {
        case .shared: "house.fill"
        case .personal: "person.fill"
        case .full: "checkmark.seal"
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension AccountEditorModel: Identifiable {}
