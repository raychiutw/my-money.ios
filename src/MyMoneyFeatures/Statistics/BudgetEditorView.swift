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
                // 月份放區塊標題:放在標籤裡「2026年10月的預算」大字級會被截成「2026年10月的…」(#157)。
                Section {
                    LabeledContent("預算") {
                        AmountField(
                            "預算", text: $model.amountText, prompt: Text("例如：8000"),
                            focus: $focusedField, equals: .amount, identifier: "budgetEditor.amount"
                        )
                    }
                    .tapToFocus($focusedField, equals: .amount)
                } header: {
                    Text(model.monthTitle)
                } footer: {
                    // 只留警告(DESIGN.md「說明文字」第 2 類)。
                    Text("設定後無法刪除。")
                }

                // 分類格放在金額下面:16 個分類的格子很高，sheet 預設只有半高，金額欄放在格子上面才看得到、填得到。
                Section("分類") {
                    CategoryGrid(categories: BudgetEditorModel.categories, selection: $model.category)
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
                SheetCloseButton { dismiss() }
                SheetConfirmButton("儲存", isDisabled: model.isSaving, identifier: "budgetEditor.save") {
                    Task {
                        if await model.save() { dismiss() }
                    }
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
