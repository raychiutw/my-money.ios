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

    /// 一個墊付帳戶的標題列:帳戶名稱、筆數與小計;有多個墊付帳戶時右邊的「⋯」選單可整組勾選、取消或只選這個帳戶。
    private func groupHeader(_ group: AdvanceGroup) -> some View {
        HStack {
            Text("\(group.title)・\(group.items.count) 筆・\(group.subtotal.formatted())")
            Spacer()
            if model.hasMultipleGroups {
                Menu {
                    Button(group.isFullySelected ? "取消這個帳戶" : "全選這個帳戶") {
                        model.setGroup(group.id, selected: !group.isFullySelected)
                    }
                    Button("僅選此帳戶") { model.selectOnly(group.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("\(group.title)的選項")
                }
                .accessibilityIdentifier("reimbursement.group.\(group.title)")
            }
        }
    }

    /// 一筆待報銷的代墊明細:開關在右邊;VoiceOver 念「備註，日期，金額」加開關狀態。
    private func itemRow(_ item: AdvanceItem) -> some View {
        Toggle(isOn: Binding(get: { model.isSelected(item.id) }, set: { _ in model.toggle(item.id) })) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.note.isEmpty ? item.category.name : "\(item.category.name) · \(item.note)")
                    Text(model.itemDateText(item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AmountText(.outflow(item.amount))
                    .monospacedDigit()
            }
        }
        .accessibilityIdentifier("reimbursement.item.\(item.id.rawValue)")
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

                // 有待報銷明細:依墊付帳戶分組逐筆勾選，預設全選(上游 `d0424df`、`42149e7`，#242)。
                if model.usesItemSelection {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }

                Section {
                    if model.usesItemSelection {
                        // 金額由勾選連動，不手動輸入。
                        AmountRow(title: "報銷金額", amount: .plain(model.selectedAmount))
                            .accessibilityIdentifier("reimbursement.amount")
                    } else {
                        LabeledContent("報銷金額") {
                            AmountField(
                                "報銷金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                                focus: $focusedField, equals: .amount, identifier: "reimbursement.amount"
                            )
                        }
                        .tapToFocus($focusedField, equals: .amount)
                    }
                    DayPickerRow(title: "撥款日期", day: $model.date)
                    LabeledContent("備註") {
                        NoteField(text: $model.note, prompt: "選填", focus: $focusedField, value: .note)
                            .accessibilityIdentifier("reimbursement.note")
                    }
                    .tapToFocus($focusedField, equals: .note)
                } footer: {
                    // 只留無法送出的原因(DESIGN.md「說明文字」第 3 類)。
                    if model.usesItemSelection, model.selectedIDs.isEmpty {
                        Text("請至少勾選一筆要報銷的代墊明細")
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .id(FormError.id)
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
            .revealsError(model.errorMessage, clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
