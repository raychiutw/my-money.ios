import MyMoneyDomain
import SwiftUI

/// 從家庭共同基金撥款報銷的 sheet(DESIGN.md「元件對照」:Form + 取消 / 確認)。成功時把後端的訊息交給 `onDone`。
struct ReimbursementView: View {
    @Bindable var model: ReimbursementModel
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
                Section {
                    AccountPicker(
                        title: "撥款公帳(家庭共同基金)", selection: $model.fromAccountID,
                        options: model.fundAccounts.map(AccountPicker.Option.init),
                        placeholder: "請選擇家庭共同基金帳戶"
                    )
                    if let balance = model.availableBalance {
                        AmountRow(title: "可用餘額", amount: balance)
                    }
                    // 可收款帳戶只有名稱和類型，不顯示其他成員個人私帳的餘額。
                    AccountPicker(
                        title: "收款帳戶(\(model.advance.memberName)的個人帳戶)", selection: $model.toAccountID,
                        options: model.receivingAccounts.map(AccountPicker.Option.init),
                        placeholder: "請選擇收款個人帳戶"
                    )
                    .disabled(model.receivingAccounts.isEmpty)
                } footer: {
                    // 只留無法撥款的原因(DESIGN.md「說明文字」第 3 類)。
                    if let note = model.receivingAccountsNote {
                        Text(note)
                    }
                }

                Section {
                    LabeledContent("報銷金額") {
                        AmountField(
                            "報銷金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $focusedField, equals: .amount, identifier: "reimbursement.amount"
                        )
                    }
                    DatePicker(
                        "撥款日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註", text: $model.note)
                        .focused($focusedField, equals: .note)
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
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("reimbursement.submit")
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
