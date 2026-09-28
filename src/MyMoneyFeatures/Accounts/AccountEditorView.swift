import MyMoneyDomain
import SwiftUI

/// 新增或編輯資金帳戶的 sheet(DESIGN.md「元件對照」:Form + 取消 / 儲存)。
struct AccountEditorView: View {
    @Bindable var model: AccountEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case amount
        case unbilled
        case creditLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.canChangeKind {
                    Picker("類型", selection: $model.kind) {
                        Text("現金錢包").tag(AccountKind.cash)
                        Text("銀行存款帳戶").tag(AccountKind.bank)
                        Text("信用卡").tag(AccountKind.creditCard)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("名稱", text: $model.name, prompt: Text(namePrompt))
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("accountEditor.name")
                    if model.showsAmountField {
                        amountRow(model.amountLabel, text: $model.amountText, field: .amount, identifier: "accountEditor.amount")
                    }
                }

                // 所有類型都能設歸屬(web 的「帳戶屬性歸屬」);預設個人私帳。
                Section {
                    Toggle(jointFundLabel, isOn: $model.isJointFund)
                        .accessibilityIdentifier("accountEditor.jointFund")
                } footer: {
                    Text(model.isJointFund ? "家庭公用帳戶將對家庭群組全體成員公開。" : "個人私帳僅你本人可見，其他家庭成員無法檢視餘額。")
                }

                if model.kind == .creditCard {
                    Section("信用卡") {
                        amountRow("未出帳金額", text: $model.unbilledText, field: .unbilled, identifier: "accountEditor.unbilled")
                        amountRow("信用額度(選填)", text: $model.creditLimitText, field: .creditLimit, identifier: "accountEditor.creditLimit", prompt: nil)
                        dayPicker("結帳日", selection: $model.statementDay)
                        dayPicker("繳款日", selection: $model.paymentDueDay)
                    }
                }

                Section("代表色") {
                    ColorChoices(selection: $model.colorHex)
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("accountEditor.error")
                    }
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("accountEditor.save")
                }
            }
            .keyboardDoneButton { focusedField = nil }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private var namePrompt: String {
        switch model.kind {
        case .cash: "例如：我的皮夾、客廳零用金盒"
        case .bank: "例如：薪轉戶"
        case .creditCard: "例如：旅遊卡"
        }
    }

    private var jointFundLabel: String {
        switch model.kind {
        case .cash: "設為家庭公用"
        case .bank: "設為家庭共同基金帳戶"
        case .creditCard: "設為家庭卡"
        }
    }

    /// `prompt` 是留空時代表的值(存成 0 的欄位才顯示「0」)。
    private func amountRow(
        _ label: String, text: Binding<String>, field: Field, identifier: String, prompt: String? = "0"
    ) -> some View {
        LabeledContent(label) {
            AmountField(
                label, text: text, prompt: prompt.map { Text(verbatim: $0) },
                focus: $focusedField, equals: field, identifier: identifier
            )
        }
    }

    private func dayPicker(_ label: String, selection: Binding<Int?>) -> some View {
        Picker(label, selection: selection) {
            Text("未設定").tag(Int?.none)
            ForEach(1...31, id: \.self) { day in
                Text("每月 \(day) 號").tag(Int?.some(day))
            }
        }
    }
}

/// 8 種代表色的圓形按鈕。每個都有 VoiceOver 念的名稱，選中的標記為已選取。
private struct ColorChoices: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccountColors.all, id: \.hex) { color in
                Button {
                    selection = color.hex
                } label: {
                    Circle()
                        .fill(Color(hex: color.hex) ?? .gray)
                        .overlay {
                            if selection == color.hex {
                                Image(systemName: "checkmark")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                        }
                        .frame(width: 32, height: 32)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selection == color.hex ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
