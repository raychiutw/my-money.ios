import MyMoneyDomain
import SwiftUI

/// 信用卡扣款還款的 sheet:待繳卡費總額與欠款公私拆解、快捷帶入、扣款帳戶、金額、日期、備註、歸屬。
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
                    LabeledContent("待繳卡費總額", value: model.card.totalDue.formatted())
                    LabeledContent("已出帳待繳金額", value: model.card.billedDebt.formatted())
                    LabeledContent("未出帳金額", value: model.card.unbilledDebt.formatted())
                    LabeledContent("家庭公帳", value: model.card.sharedDebt.formatted())
                    LabeledContent("個人私帳", value: model.card.personalDebt.formatted())
                } header: {
                    Text(model.card.name)
                } footer: {
                    Text("先沖已出帳待繳款，不足的部分再沖未出帳款。會產生兩筆「信用卡還款」交易記錄：銀行存款帳戶一筆支出、信用卡一筆收入。")
                }
                .monospacedDigit()

                Section {
                    Picker("扣款帳戶", selection: $model.bankAccountID) {
                        Text("請選擇扣款帳戶").tag(AccountID?.none)
                        ForEach(model.bankAccounts) { bank in
                            Text("\(bank.name)(餘額 \(bank.balance.formatted()))").tag(AccountID?.some(bank.id))
                        }
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
                    Picker("歸屬", selection: $model.isShared) {
                        Text("家庭公帳").tag(true)
                        Text("個人私帳").tag(false)
                    }
                    .pickerStyle(.segmented)
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
            .keyboardDoneButton { focusedField = nil }
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
