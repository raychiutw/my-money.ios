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
                    EmojiChoices(selection: $model.emoji)
                }

                Section {
                    TextField("名稱", text: $model.name, prompt: Text("例如：日本沖繩旅遊、緊急備用金"))
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("goalEditor.name")
                    amountField("目標金額", text: $model.targetAmountText, field: .target, identifier: "goalEditor.target")
                    amountField("每月預留(選填)", text: $model.monthlyReserveText, field: .reserve, identifier: "goalEditor.reserve")
                }

                Section {
                    Toggle("截止日", isOn: $model.hasDeadline)
                    if model.hasDeadline {
                        DatePicker(
                            "日期",
                            selection: Binding(get: { model.deadline.startOfDay }, set: { model.deadline = CalendarDay(date: $0) }),
                            displayedComponents: .date
                        )
                        .calendarDayTimeZone()
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
                    .accessibilityIdentifier("goalEditor.save")
                }
            }
            .keyboardDoneButton { focusedField = nil }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private func amountField(_ label: String, text: Binding<String>, field: Field, identifier: String) -> some View {
        LabeledContent(label) {
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .numberKeyboard()
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// 12 種 emoji 的按鈕，選中的標記為已選取。
private struct EmojiChoices: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44)), count: 6), spacing: 8) {
            ForEach(SavingsGoalEditorModel.emojiChoices, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selection == emoji ? Color.accentColor : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == emoji ? .isSelected : [])
            }
        }
    }
}
