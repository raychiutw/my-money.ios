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
                        AmountRow(title: "可用餘額", amount: .plain(balance))
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
                    .tapToFocus($focusedField, equals: .amount)
                    DayPickerRow(title: "撥款日期", day: $model.date)
                    LabeledContent("備註") {
                        NoteField(text: $model.note, prompt: "選填", focus: $focusedField, value: .note)
                            .accessibilityIdentifier("reimbursement.note")
                    }
                    .tapToFocus($focusedField, equals: .note)
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
                SheetCloseButton { dismiss() }
                SheetConfirmButton("確認", isDisabled: !model.canSubmit, identifier: "reimbursement.submit") {
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
