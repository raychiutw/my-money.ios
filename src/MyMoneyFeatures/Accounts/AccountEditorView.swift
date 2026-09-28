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
                        Text("銀行存款帳戶").tag(AccountKind.bank)
                        Text("信用卡").tag(AccountKind.creditCard)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("名稱", text: $model.name, prompt: Text(model.kind == .bank ? "例如：薪轉戶、零用金" : "例如：旅遊卡"))
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("accountEditor.name")
                    amountField(model.amountLabel, text: $model.amountText, field: .amount, identifier: "accountEditor.amount")
                }

                if model.kind == .bank {
                    Section {
                        Toggle("設為家庭共同基金帳戶", isOn: $model.isJointFund)
                            .accessibilityIdentifier("accountEditor.jointFund")
                    } footer: {
                        Text("供家庭公帳的採買扣款，以及撥付代墊請款報銷。")
                    }
                }

                if model.kind == .creditCard {
                    Section("信用卡") {
                        amountField("未出帳金額", text: $model.unbilledText, field: .unbilled, identifier: "accountEditor.unbilled")
                        amountField("信用額度(選填)", text: $model.creditLimitText, field: .creditLimit, identifier: "accountEditor.creditLimit", prompt: nil)
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

    /// `prompt` 是留空時代表的值(存成 0 的欄位才顯示「0」)。
    private func amountField(
        _ label: String, text: Binding<String>, field: Field, identifier: String, prompt: String? = "0"
    ) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: prompt.map { Text(verbatim: $0) })
                .multilineTextAlignment(.trailing)
                .numberKeyboard()
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(identifier)
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
                                    .font(.caption.bold())
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
