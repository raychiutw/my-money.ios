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
    /// 分類是依備註自動預選時的提示文字(記一筆才有);編輯既有交易一律沒有。
    var categoryHintText: String? { get }
    func prepare() async
    /// 使用者手動選分類:記一筆會鎖定，之後不再依備註覆蓋。
    func chooseCategory(_ category: TransactionCategory)
    /// 載入備註歷史(智慧推薦的第一層);失敗時不擋記帳。
    func loadNoteHistory() async
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
                // 歸屬:2 個選項用內嵌選擇列，點一下就選，body 字級不縮小(ADR-0004、#90)。
                Section("歸屬") {
                    Picker("歸屬", selection: $model.isShared) {
                        Text("家庭公帳").tag(true)
                        Text("個人私帳").tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("金額") {
                        AmountField(
                            "金額", text: $model.amountText, prompt: Text(verbatim: "0"),
                            focus: $focusedField, equals: .amount, identifier: "quickEntry.amount"
                        )
                    }
                }

                // 備註放在金額正下方、分類格上面:金額欄一打開就對焦，數字鍵盤蓋住下半部，16 格分類很高，
                // 備註放在格子下面就看不到也捲不到;放這裡，打完金額就是備註，推薦提示緊貼在備註下面，
                // 分類格就在下面跟著變(#99)。
                Section {
                    TextField("備註(選填)", text: $model.note)
                        .focused($focusedField, equals: .note)
                        .accessibilityIdentifier("quickEntry.note")
                } footer: {
                    // 依備註自動預選分類時的提示，放在備註欄正下方:打字時看得到，不必捲回分類格。
                    if let hint = model.categoryHintText {
                        Label(hint, systemImage: "sparkles")
                            .accessibilityIdentifier("quickEntry.categoryHint")
                    }
                }

                // 分類攤開成格，點一下就選(ADR-0004、#89)。
                Section("分類") {
                    CategoryGrid(
                        categories: model.categories,
                        selection: Binding(get: { model.category }, set: { model.chooseCategory($0) })
                    )
                }

                Section {
                    AccountPicker(title: "帳戶", selection: $model.accountID, options: model.accounts.map(AccountPicker.Option.init))
                    DatePicker(
                        "日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
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
            // 歷史另外載入:很慢或失敗都不影響記帳，只是少了歷史推薦。
            .task { await model.loadNoteHistory() }
            .onChange(of: model.categoryHintText) { _, hint in
                if let hint {
                    AccessibilityNotification.Announcement(hint).post()
                }
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }
}
