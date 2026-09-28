import MyMoneyDomain
import SwiftUI

/// 「記一筆」與「編輯交易紀錄」共用的表單。兩者的欄位相同，只有標題、驗證訊息與儲存後的行為不同。
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

/// 交易紀錄的表單 sheet。「記一筆」的 model 每個 session 一份，下一筆會沿用上一筆的類型、分類、帳戶和公私帳。
struct TransactionFormView<Model: TransactionForm>: View {
    @Bindable var model: Model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("歸屬", selection: $model.isShared) {
                        Text("家庭公帳").tag(true)
                        Text("個人私帳").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("類型", selection: $model.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("金額") {
                        TextField("金額", text: $model.amountText, prompt: Text(verbatim: "0"))
                            .multilineTextAlignment(.trailing)
                            .numberKeyboard()
                            .monospacedDigit()
                            .focused($isAmountFocused)
                            .accessibilityIdentifier("quickEntry.amount")
                    }
                    Picker("分類", selection: $model.category) {
                        ForEach(model.categories, id: \.self) { category in
                            Label(category.name, systemImage: category.symbolName).tag(category)
                        }
                    }
                    Picker("帳戶", selection: $model.accountID) {
                        ForEach(model.accounts) { account in
                            Text(accountTitle(account)).tag(Optional(account.id))
                        }
                    }
                    DatePicker(
                        "日期",
                        selection: Binding(get: { model.date.startOfDay }, set: { model.date = CalendarDay(date: $0) }),
                        displayedComponents: .date
                    )
                    .calendarDayTimeZone()
                    TextField("備註(選填)", text: $model.note)
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
            .keyboardDoneButton { isAmountFocused = false }
            .task {
                await model.prepare()
                isAmountFocused = true
            }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private func accountTitle(_ account: Account) -> String {
        switch account {
        case .bank(let bank): "\(bank.name)(銀行存款帳戶)"
        case .creditCard(let card): "\(card.name)(信用卡)"
        }
    }
}
