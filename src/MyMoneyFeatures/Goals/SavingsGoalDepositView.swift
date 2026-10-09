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
                    .tapToFocus($focusedField, equals: .amount)
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .id(FormError.id)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("goalDeposit.error")
                    }
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("存入", isDisabled: model.isSaving, identifier: "goalDeposit.save") {
                    Task {
                        if await model.save() { dismiss() }
                    }
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .revealsError(model.errorMessage, clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
