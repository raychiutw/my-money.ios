import MyMoneyDomain
import SwiftUI

/// ATM 提款／帳戶互轉的 sheet(DESIGN.md「元件對照」:Form + 取消 / 確認)。成功時把後端的訊息交給 `onDone`。
struct TransferView: View {
    @Bindable var model: TransferModel
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
        case note
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.hasQuickScenarios {
                    Section("快捷情境") {
                        Button("ATM 提款至皮夾", systemImage: "banknote") { model.applyATMScenario() }
                            .accessibilityIdentifier("transfer.atm")
                        Button("存款至銀行", systemImage: "building.columns") { model.applyDepositScenario() }
                            .accessibilityIdentifier("transfer.deposit")
                    }
                }

                Section {
                    AccountPicker(
                        title: "轉出帳戶", selection: $model.fromAccountID, options: model.candidates.map(AccountPicker.Option.init),
                        placeholder: "請選擇轉出帳戶"
                    )
                    if let balance = model.availableBalance {
                        AmountRow(title: "可用餘額", amount: balance)
                    }
                    AccountPicker(
                        title: "轉入帳戶", selection: $model.toAccountID, options: model.toCandidates.map(AccountPicker.Option.init),
                        placeholder: "請選擇轉入帳戶"
                    )
                }

                Section {
                    LabeledContent("金額") {
                        AmountField(
                            "金額", text: $model.amountText, prompt: Text("例如：3000"),
                            focus: $focusedField, equals: .amount, identifier: "transfer.amount"
                        )
                    }
                    .tapToFocus($focusedField, equals: .amount)
                    DayPickerRow(title: "日期", day: $model.date)
                    LabeledContent("備註") {
                        NoteField(text: $model.note, prompt: "例如：超商 ATM 提款", focus: $focusedField, value: .note)
                            .accessibilityIdentifier("transfer.note")
                    }
                    .tapToFocus($focusedField, equals: .note)
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("transfer.error")
                    }
                }
            }
            .navigationTitle("ATM 提款／轉帳")
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("確認", isDisabled: model.isSaving, identifier: "transfer.submit") {
                    Task {
                        if let message = await model.submit() {
                            dismiss()
                            onDone(message)
                        }
                    }
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .task { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
