import MyMoneyDomain
import SwiftUI

/// ATM 提款／帳戶互轉的 sheet(DESIGN.md「元件對照」:Form + 取消 / 確認)。成功時把後端的訊息交給 `onDone`。
struct TransferView: View {
    @Bindable var model: TransferModel
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

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
                    Picker("轉出帳戶", selection: $model.fromAccountID) {
                        ForEach(model.candidates) { account in
                            Text(account.menuTitleWithBalance).tag(Optional(account.id))
                        }
                    }
                    Picker("轉入帳戶", selection: $model.toAccountID) {
                        ForEach(model.toCandidates) { account in
                            Text(account.menuTitleWithBalance).tag(Optional(account.id))
                        }
                    }
                } footer: {
                    Text("帳戶間互轉或 ATM 提領現鈔只是資金調度，不會被列為生活消費支出。")
                }

                Section {
                    LabeledContent("金額") {
                        AmountField(
                            "金額", text: $model.amountText, prompt: Text("例如：3000"),
                            focus: $isAmountFocused, equals: true, identifier: "transfer.amount"
                        )
                    }
                    DatePicker(
                        "日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註(選填)", text: $model.note, prompt: Text("例如：超商 ATM 提款"))
                        .accessibilityIdentifier("transfer.note")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        Task {
                            if let message = await model.submit() {
                                dismiss()
                                onDone(message)
                            }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("transfer.submit")
                }
            }
            .keyboardDoneButton { isAmountFocused = false }
            .task { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
