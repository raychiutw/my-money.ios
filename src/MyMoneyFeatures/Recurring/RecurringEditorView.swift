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

    @ViewBuilder
    private var monthPicker: some View {
        let picker = Picker(model.monthTitle, selection: $model.monthOfCycle) {
            ForEach(model.monthOptions) { option in
                Text(option.title).tag(option.value)
            }
        }
        if model.monthOptions.count <= 3 {
            picker
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("recurringEditor.month")
        } else {
            picker
                .navigationLinkStyle()
                .accessibilityIdentifier("recurringEditor.month")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 欄位要有看得見的標籤，placeholder 只放範例(DESIGN.md「列與欄位」第 8 條，#78)。
                    LabeledContent("名稱") {
                        TextField(
                            "名稱",
                            text: $model.name,
                            prompt: Text(model.type == .expense ? "例如：房租、電信費、健身房月費" : "例如：每月薪資、租金收益")
                        )
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("recurringEditor.name")
                    }
                    LabeledContent("每期金額") {
                        AmountField(
                            "每期金額", text: $model.amountText, prompt: Text("例如：15000"),
                            focus: $focusedField, equals: .amount, identifier: "recurringEditor.amount"
                        )
                    }
                }

                // 週期只有 5 個選項:內嵌選擇列，點一下就選(ADR-0004、#91)。
                Section("週期") {
                    Picker("週期", selection: $model.cycle) {
                        ForEach(RecurringCycle.allCases, id: \.self) { cycle in
                            Text(cycle.pickerLabel).tag(cycle)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // 繳費月份(#131):月繳沒有;雙月繳 2 個、季繳 3 個用內嵌選擇列，半年繳 6 個、年繳 12 個推入清單頁。
                if !model.monthOptions.isEmpty {
                    Section(model.monthTitle) {
                        monthPicker
                    }
                }

                Section {
                    // 1～31 號有 31 個選項:推入清單頁，選了自動返回。
                    Picker(model.type == .expense ? "扣款日" : "入帳日", selection: $model.dayOfCycle) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day) 號").tag(day)
                        }
                    }
                    .navigationLinkStyle()
                    AccountPicker(
                        title: "關聯帳戶", selection: $model.accountID, options: model.accounts.map(AccountPicker.Option.init),
                        noneTitle: "無特定帳戶"
                    )
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
                // 週期支出／週期收入放在導覽列中間(#65,跟記一筆一樣),不另外佔表單一列。
                ToolbarItem(placement: .principal) {
                    Picker("類型", selection: $model.type) {
                        Text("週期支出").tag(TransactionType.expense)
                        Text("週期收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
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
            .keyboardDismissal(clearing: $focusedField)
            .task { await model.prepare() }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
