import SwiftUI

/// 存入儲蓄目標的 sheet。
struct SavingsGoalDepositView: View {
    @Bindable var model: SavingsGoalDepositModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.summary)
                        .monospacedDigit()
                    LabeledContent("本次存入金額") {
                        AmountField(
                            "本次存入金額", text: $model.amountText, prompt: Text("例如：3000"),
                            focus: $focusedField, equals: .amount, identifier: "goalDeposit.amount"
                        )
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("goalDeposit.error")
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
                    Button("存入") {
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("goalDeposit.save")
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
