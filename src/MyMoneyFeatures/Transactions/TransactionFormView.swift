import MyMoneyDomain
import SwiftUI

/// 「記一筆」與「編輯交易記錄」共用的表單。兩者的欄位相同，只有標題、驗證訊息與儲存後的行為不同。
@MainActor
public protocol TransactionForm: AnyObject, Observable {
    var title: String { get }
    var accounts: [Account] { get }
    var isShared: Bool { get set }
    var type: TransactionType { get set }
    var category: TransactionCategory { get set }
    var amountText: String { get set }
    var note: String { get set }
    var date: CalendarDay { get set }
    var accountID: AccountID? { get set }
    var categories: [TransactionCategory] { get }
    var errorMessage: String? { get }
    var isSaving: Bool { get }
    func prepare() async
    func save() async -> Bool
}

extension QuickEntryModel: TransactionForm {}
extension TransactionEditorModel: TransactionForm {}

/// 交易記錄的表單 sheet。「記一筆」的 model 每個 session 一份，下一筆會沿用上一筆的類型、分類、帳戶和公私帳。
struct TransactionFormView<Model: TransactionForm>: View {
    @Bindable var model: Model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case amount
        case note
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 表單裡一般的選擇列(#65):標籤在左、值在右，跟著 Dynamic Type。
                    Picker("歸屬", selection: $model.isShared) {
                        Text("家庭公帳").tag(true)
                        Text("個人私帳").tag(false)
                    }
                    .accessibilityIdentifier("quickEntry.ownership")
                    LabeledContent("金額") {
                        AmountField(
                            "金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $focusedField, equals: .amount, identifier: "quickEntry.amount"
                        )
                    }
                    Picker("分類", selection: $model.category) {
                        ForEach(model.categories, id: \.self) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category)
                        }
                    }
                    Picker("帳戶", selection: $model.accountID) {
                        ForEach(model.accounts) { account in
                            Text(account.menuTitle).tag(Optional(account.id))
                        }
                    }
                    DatePicker(
                        "日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註(選填)", text: $model.note)
                        .focused($focusedField, equals: .note)
                        .accessibilityIdentifier("quickEntry.note")
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("quickEntry.error")
                    }
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                // 支出／收入放在導覽列中間(#65,HIG 分段控制一節舉的行事曆「新增事件」),不另外佔表單一列。
                ToolbarItem(placement: .principal) {
                    Picker("類型", selection: $model.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
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
                    .accessibilityIdentifier("quickEntry.save")
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .task {
                await model.prepare()
                focusedField = .amount
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
