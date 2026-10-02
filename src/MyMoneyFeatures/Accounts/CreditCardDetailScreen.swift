import MyMoneyDomain
import SwiftUI

/// 信用卡詳細頁(#73,DESIGN.md「導覽」):從帳戶頁或總覽的信用卡精簡列 push 進來。
///
/// 每個欄位一列(`LabeledContent`):「卡費」「設定」兩區;「操作」有「繳款」選單、出帳作業(有未出帳款才有)和校準未出帳。
/// toolbar 的「編輯」打開資產帳戶編輯器。繳款、出帳作業、校準、編輯成功後資料版本遞增，這一頁重新取得。
struct CreditCardDetailScreen: View {
    /// 由路由(`navigationDestination`)建立後傳入。父層重畫時路由會再建立一份新的 model,
    /// 用 `@State` 留住第一次傳入的那一份，送出中的狀態和打開的 sheet 才不會被換掉。
    @State private var model: CreditCardDetailModel
    @State private var payment: CardPaymentModel?
    @State private var editor: AccountEditorModel?
    @State private var isConfirmingRollover = false
    @State private var isConfirmingReconcile = false
    @Environment(\.dismiss) private var dismiss

    init(model: CreditCardDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            feesSection
            settingsSection
            // 個人信用卡只有持卡人能繳款、出帳、校準(上游 ADR 0013、#133)。
            if model.canOperate {
                actionsSection
            }
        }
        .navigationTitle(model.card.name)
        .inlineNavigationTitle()
        .toolbar {
            // HIG Toolbars:編輯這類難用符號表達的動作可以用文字。
            if model.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("編輯") { editor = model.makeEditor() }
                        .accessibilityIdentifier("cardDetail.edit")
                }
            }
        }
        .refreshable { await model.load() }
        // 資料版本改變(這一頁或其他畫面新增、修改、刪除成功)就重新取得。
        .task(id: model.dataVersion.value) {
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
        .confirmationDialog("結帳日出帳作業", isPresented: $isConfirmingRollover, titleVisibility: .visible) {
            Button("出帳作業") {
                Task { await model.rollOver() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.rolloverConfirmation)
        }
        .confirmationDialog("校準未出帳", isPresented: $isConfirmingReconcile, titleVisibility: .visible) {
            Button("校準") {
                Task { await model.reconcile() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.reconcileConfirmation)
        }
        .alert(
            "無法完成",
            isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
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
            LabeledContent("信用卡待繳總額", value: card.totalDue.formatted())
            LabeledContent("已出帳待繳款", value: card.billedDebt.formatted())
            LabeledContent("未出帳款", value: card.unbilledDebt.formatted())
            // 欠款公私拆解(畫面上原本叫「負債性質拆解」,section 標題已經表達，不加前綴)。
            LabeledContent("家庭代墊公帳", value: card.sharedDebt.formatted())
            LabeledContent("個人私帳消費", value: card.personalDebt.formatted())
        }
        .monospacedDigit()
    }

    private var settingsSection: some View {
        Section("設定") {
            LabeledContent("信用額度", value: card.creditLimit?.formatted() ?? "未設定")
            // 沒有設定信用額度時沒有剩餘額度(CONTEXT.md);最小是 0,web 在 82d9124 拿掉了「額度不足」的警示。
            if let remaining = card.remainingCredit {
                LabeledContent("剩餘額度", value: remaining.formatted())
            }
            LabeledContent("結帳日", value: Self.monthlyDay(card.statementDay))
            LabeledContent("繳款日", value: Self.monthlyDay(card.paymentDueDay))
        }
        .monospacedDigit()
    }

    /// 例如「每月 15 日」;沒有設定時是「未設定」。
    private static func monthlyDay(_ day: Int?) -> String {
        day.map { "每月 \($0) 日" } ?? "未設定"
    }

    private var actionsSection: some View {
        Section("操作") {
            // 三個還款入口收進一個 pull-down(HIG Pull-down buttons),沒有對應欠款的項目隱藏。
            if !model.paymentPresets.isEmpty {
                Menu {
                    ForEach(model.paymentPresets, id: \.self) { preset in
                        Button(preset.title, systemImage: preset.systemImage) {
                            payment = model.makePayment(preset)
                        }
                    }
                } label: {
                    // 跟同一區的按鈕一樣整列都點得到(`Menu` 預設只有文字的範圍)。
                    Label("繳款", systemImage: "creditcard.and.123")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("cardDetail.pay")
            }
            if model.showsRollover {
                Button("出帳作業", systemImage: "calendar.badge.clock") { isConfirmingRollover = true }
                    .accessibilityIdentifier("cardDetail.rollover")
            }
            Button(model.isReconciling ? "校準中…" : "校準未出帳", systemImage: "arrow.triangle.2.circlepath") {
                isConfirmingReconcile = true
            }
            .disabled(model.isReconciling)
            .accessibilityIdentifier("cardDetail.reconcile")
        }
    }
}

extension CardPaymentModel.Preset {
    /// 詳細頁「繳款」選單和精簡列長按選單的項目。
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
