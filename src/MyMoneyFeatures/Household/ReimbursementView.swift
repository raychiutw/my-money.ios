import MyMoneyDomain
import SwiftUI

/// 從家庭共同基金撥款報銷的 sheet(DESIGN.md「元件對照」:Form + 取消 / 確認)。成功時把後端的訊息交給 `onDone`。
struct ReimbursementView: View {
    @Bindable var model: ReimbursementModel
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("撥款公帳(家庭共同基金)", selection: $model.fromAccountID) {
                        ForEach(model.fundAccounts) { account in
                            Text(model.title(for: account)).tag(Optional(account.id))
                        }
                    }
                    Picker("收款帳戶(我的個人帳戶)", selection: $model.toAccountID) {
                        ForEach(model.receivingAccounts) { account in
                            Text(model.title(for: account)).tag(Optional(account.id))
                        }
                    }
                } footer: {
                    Text("從家庭共同基金扣款，撥入個人帳戶，自動結清公帳代墊款，不會被重複計入家庭消費支出。")
                }

                Section {
                    LabeledContent("報銷金額") {
                        AmountField(
                            "報銷金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $isAmountFocused, equals: true, identifier: "reimbursement.amount"
                        )
                    }
                    DatePicker(
                        "撥款日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註", text: $model.note)
                        .accessibilityIdentifier("reimbursement.note")
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("reimbursement.error")
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
                    Button("確認") {
                        Task {
                            if let message = await model.submit() {
                                dismiss()
                                onDone(message)
                            }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("reimbursement.submit")
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
