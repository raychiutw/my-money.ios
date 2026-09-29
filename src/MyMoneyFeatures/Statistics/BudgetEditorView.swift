import MyMoneyDomain
import SwiftUI

/// 設定預算額度的 sheet(DESIGN.md「元件對照」:Form + 取消 / 儲存)。
struct BudgetEditorView: View {
    @Bindable var model: BudgetEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("分類", selection: $model.category) {
                        ForEach(BudgetEditorModel.categories, id: \.self) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category)
                        }
                    }
                    LabeledContent("\(String(model.month.year)) 年 \(model.month.month) 月的預算") {
                        AmountField(
                            "預算", text: $model.amountText, prompt: Text("例如：8000"),
                            focus: $focusedField, equals: .amount, identifier: "budgetEditor.amount"
                        )
                    }
                } footer: {
                    Text("預算額度每個月各自一份，設定後無法刪除。")
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("budgetEditor.error")
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
                    .accessibilityIdentifier("budgetEditor.save")
                }
            }
            .keyboardDoneButton(clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
