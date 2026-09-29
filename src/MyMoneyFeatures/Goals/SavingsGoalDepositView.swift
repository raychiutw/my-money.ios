import SwiftUI

/// 存入儲蓄目標的 sheet。
struct SavingsGoalDepositView: View {
    @Bindable var model: SavingsGoalDepositModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.summary)
                        .monospacedDigit()
                    LabeledContent("本次存入金額") {
                        AmountField(
                            "本次存入金額", text: $model.amountText, prompt: Text("例如：3000"),
                            focus: $isAmountFocused, equals: true, identifier: "goalDeposit.amount"
                        )
                    }
                } footer: {
                    Text("存入只記在儲蓄目標上，不會動到任何資產帳戶。")
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
            .keyboardDoneButton { isAmountFocused = false }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
