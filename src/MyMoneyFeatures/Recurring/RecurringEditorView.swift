import MyMoneyDomain
import SwiftUI

/// 新增或編輯週期收支的 sheet(DESIGN.md「元件對照」:Form + 取消 / 儲存)。
struct RecurringEditorView: View {
    @Bindable var model: RecurringEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case amount
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("類型", selection: $model.type) {
                    Text("週期支出").tag(TransactionType.expense)
                    Text("週期收入").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    TextField(
                        "名稱",
                        text: $model.name,
                        prompt: Text(model.type == .expense ? "例如：房租、電信費、健身房月費" : "例如：每月薪資、租金收益")
                    )
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("recurringEditor.name")
                    LabeledContent("每期金額") {
                        AmountField(
                            "每期金額", text: $model.amountText, prompt: Text("例如：15000"),
                            focus: $focusedField, equals: .amount, identifier: "recurringEditor.amount"
                        )
                    }
                }

                Section {
                    Picker("週期", selection: $model.cycle) {
                        ForEach(RecurringCycle.allCases, id: \.self) { cycle in
                            Text(cycle.pickerLabel).tag(cycle)
                        }
                    }
                    Picker(model.type == .expense ? "扣款日" : "入帳日", selection: $model.dayOfCycle) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day) 號").tag(day)
                        }
                    }
                    Picker("關聯帳戶", selection: $model.accountID) {
                        Text("無特定帳戶").tag(AccountID?.none)
                        ForEach(model.accounts) { account in
                            Text(account.menuTitle).tag(AccountID?.some(account.id))
                        }
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("recurringEditor.error")
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
                    Button("儲存") {
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("recurringEditor.save")
                }
            }
            .keyboardDoneButton(clearing: $focusedField)
            .task { await model.prepare() }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
