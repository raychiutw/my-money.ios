import SwiftUI

/// 編輯撥款沖帳紀錄的表單(上游 ADR 0031,#314):金額、日期、備註;收款帳戶不能改。
struct ReimbursementEditView: View {
    @Bindable var model: ReimbursementEditModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
        case note
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("reimbursementEdit.error")
                    }
                }
                Section {
                    DayPickerRow(title: "撥款日期", day: $model.date)
                    AmountField(
                        "報銷金額", text: $model.amountText, focus: $focusedField, equals: .amount, identifier: "reimbursementEdit.amount"
                    )
                    .tapToFocus($focusedField, equals: .amount)
                } footer: {
                    Text("修改金額或日期會同步共同基金與收款帳戶兩邊。金額不能低於已結清代墊明細的合計。")
                }
                Section {
                    NoteField(text: $model.note, focus: $focusedField, value: .note, identifier: "reimbursementEdit.note")
                        .tapToFocus($focusedField, equals: .note)
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("儲存", isDisabled: model.isSaving, identifier: "reimbursementEdit.save") {
                    Task {
                        if await model.save() { dismiss() }
                    }
                }
            }
            .keyboardDismissal(clearing: $focusedField)
        }
    }
}

extension ReimbursementEditModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
