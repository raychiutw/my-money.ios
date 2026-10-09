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

    /// 負債列(#202):金額是紅色負數,零不帶號、一般色。
    private func debtRow(_ title: String, _ amount: Money) -> some View {
        LabeledContent(title) {
            AmountText(.outflow(amount))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.isMaskedCard {
                        // 他人的卡只看得到家庭代墊(上游 ADR 0015)。
                        debtRow("家庭公帳代墊待繳總額", model.card.sharedDebt)
                    } else {
                        debtRow("信用卡待繳總額", model.card.totalDue)
                        debtRow("已出帳待繳款", model.card.billedDebt)
                        debtRow("未出帳款", model.card.unbilledDebt)
                        debtRow(OwnershipName.household, model.card.sharedDebt)
                        debtRow(OwnershipName.personal, model.card.personalDebt)
                    }
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
                        AmountRow(title: "可用餘額", amount: .plain(balance))
                    }
                    LabeledContent("繳款金額") {
                        AmountField(
                            "繳款金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $focusedField, equals: .amount, identifier: "cardPayment.amount"
                        )
                    }
                    .tapToFocus($focusedField, equals: .amount)
                    DayPickerRow(title: "日期", day: $model.date)
                    LabeledContent("備註") {
                        NoteField(text: $model.note, prompt: "選填", focus: $focusedField, value: .note)
                            .accessibilityIdentifier("cardPayment.note")
                    }
                    .tapToFocus($focusedField, equals: .note)
                }

                if model.isMaskedCard {
                    // 他人的私卡只能從共同基金繳家庭代墊，歸屬固定公帳，不給選(上游 ADR 0015)。
                    Section("歸屬") {
                        Label("\(OwnershipName.household)（僅限自家庭共同帳戶沖抵他人私卡之家庭代墊款）", systemImage: "house.fill")
                            .accessibilityIdentifier("cardPayment.fixedShared")
                    }
                } else {
                    // 歸屬:2 個選項用內嵌選擇列，點一下就選(ADR-0004、#90)。
                    Section("歸屬") {
                        InlineChoiceRows([(true, OwnershipName.household), (false, OwnershipName.personal)], selection: $model.isShared)
                    }
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
                SheetCloseButton { dismiss() }
                SheetConfirmButton("還款", isDisabled: model.isSaving, identifier: "cardPayment.submit") {
                    submit(confirmedLowBalance: false)
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            // 送出之後才知道餘額不足,觸發的是導覽列的 ✓ 鈕之後的非同步結果,沒有適合的錨點:
            // 用 alert(置中、寬度固定、大字級會折行)，不用錨點亂指的泡泡(#169)。
            .alert("扣款帳戶餘額不足", isPresented: $isLowBalanceConfirming) {
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
