import MyMoneyDomain
import SwiftUI

/// 信用卡扣款還款的 sheet:信用卡待繳總額與欠款公私拆解、快捷帶入、扣款帳戶、金額、日期、備註、歸屬。
struct CardPaymentView: View {
    @Bindable var model: CardPaymentModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var isLowBalanceConfirming = false

    private enum Field {
        case amount
        case note
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("信用卡待繳總額", value: model.card.totalDue.formatted())
                    LabeledContent("已出帳待繳款", value: model.card.billedDebt.formatted())
                    LabeledContent("未出帳款", value: model.card.unbilledDebt.formatted())
                    LabeledContent("家庭公帳", value: model.card.sharedDebt.formatted())
                    LabeledContent("個人私帳", value: model.card.personalDebt.formatted())
                } header: {
                    Text(model.card.name)
                }
                .monospacedDigit()

                Section {
                    AccountPicker(
                        title: "扣款帳戶", selection: $model.bankAccountID, options: model.bankAccounts.map(AccountPicker.Option.init),
                        placeholder: "請選擇扣款銀行"
                    )
                    if let balance = model.availableBalance {
                        AmountRow(title: "可用餘額", amount: balance)
                    }
                    LabeledContent("繳款金額") {
                        AmountField(
                            "繳款金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $focusedField, equals: .amount, identifier: "cardPayment.amount"
                        )
                    }
                    DatePicker(
                        "日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註", text: $model.note)
                        .focused($focusedField, equals: .note)
                }

                // 歸屬:2 個選項用內嵌選擇列，點一下就選(ADR-0004、#90)。
                Section("歸屬") {
                    Picker("歸屬", selection: $model.isShared) {
                        Text("家庭公帳").tag(true)
                        Text("個人私帳").tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("cardPayment.error")
                    }
                }
            }
            .navigationTitle("信用卡扣款還款")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("還款") { submit(confirmedLowBalance: false) }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("cardPayment.submit")
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .confirmationDialog(
                "扣款帳戶餘額不足",
                isPresented: $isLowBalanceConfirming,
                titleVisibility: .visible
            ) {
                Button("仍要扣款") { submit(confirmedLowBalance: true) }
                Button("取消", role: .cancel) {}
            } message: {
                Text(model.lowBalanceConfirmation ?? "")
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private func submit(confirmedLowBalance: Bool) {
        Task {
            switch await model.submit(confirmedLowBalance: confirmedLowBalance) {
            case .paid: dismiss()
            case .needsConfirmation: isLowBalanceConfirming = true
            case .invalid, .failed: break
            }
        }
    }
}
