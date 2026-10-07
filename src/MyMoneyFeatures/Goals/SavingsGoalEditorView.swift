import MyMoneyDomain
import SwiftUI

/// 建立或編輯儲蓄目標的 sheet(DESIGN.md「元件對照」:Form + 取消 / 儲存)。
struct SavingsGoalEditorView: View {
    @Bindable var model: SavingsGoalEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case target
        case reserve
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("圖示") {
                    IconChoices(selection: $model.icon)
                }

                Section {
                    // 欄位要有看得見的標籤，placeholder 只放範例(DESIGN.md「列與欄位」第 8 條，#78)。
                    LabeledContent("名稱") {
                        TextField("名稱", text: $model.name, prompt: Text("例如：日本沖繩旅遊、緊急備用金"))
                            .focused($focusedField, equals: .name)
                            .accessibilityIdentifier("goalEditor.name")
                    }
                    .tapToFocus($focusedField, equals: .name)
                    amountRow("目標金額", text: $model.targetAmountText, field: .target, identifier: "goalEditor.target")
                    amountRow("每月預留(選填)", text: $model.monthlyReserveText, field: .reserve, identifier: "goalEditor.reserve")
                }

                Section {
                    Toggle("截止日", isOn: $model.hasDeadline)
                        .tint(Color.ciFill)
                    if model.hasDeadline {
                        DayPickerRow(title: "日期", day: $model.deadline)
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("goalEditor.error")
                    }
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("儲存", isDisabled: model.isSaving, identifier: "goalEditor.save") {
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
    }

    private func amountRow(_ label: String, text: Binding<String>, field: Field, identifier: String) -> some View {
        LabeledContent(label) {
            AmountField(label, text: text, focus: $focusedField, equals: field, identifier: identifier)
        }
        .tapToFocus($focusedField, equals: field)
    }
}

/// 12 款圖示(SF Symbol)的按鈕，選中的標記為已選取。
private struct IconChoices: View {
    @Binding var selection: SavingsGoalIcon

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44)), count: 6), spacing: 8) {
            ForEach(SavingsGoalIcon.allCases, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon.symbolName)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        // 選取(ADR-0009、#177):CI 外框加淡底。
                        .background(selection == icon ? Color.ciFill.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selection == icon ? Color.ciFill : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(selection == icon ? .isSelected : [])
            }
        }
    }
}
