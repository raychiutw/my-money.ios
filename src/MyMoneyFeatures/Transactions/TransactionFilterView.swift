import MyMoneyDomain
import SwiftUI

/// 交易頁的「篩選」sheet(DESIGN.md「導覽」,#74):視角、起日、迄日、類型、分類。
///
/// 改的是畫面 model 裡的一份草稿：按「完成」才套用，只查詢一次;按「取消」或往下滑關掉都不變。
/// 沒有文字欄位，所以不用收起鍵盤(`keyboardDismissal`)。
struct TransactionFilterView: View {
    @Bindable var model: TransactionsModel

    var body: some View {
        NavigationStack {
            Form {
                // 分段控制的標籤不會顯示，用 section 標題當看得見的標籤(DESIGN.md「列與欄位」第 8 條)。
                Section("視角") {
                    SegmentedPicker(
                        "視角", options: ViewScope.allCases.map { ($0, $0.title) }, selection: $model.filterDraft.scope,
                        identifier: "transactionFilter.scope", fillsWidth: true
                    )
                }

                Section {
                    DatePicker("起日", selection: day(\.from), displayedComponents: .date)
                        .accessibilityIdentifier("transactionFilter.from")
                    // 迄日不早於起日。
                    DatePicker("迄日", selection: day(\.to), in: model.filterDraft.from.startOfDay..., displayedComponents: .date)
                        .accessibilityIdentifier("transactionFilter.to")
                    Button {
                        model.resetFilterDraftToThisMonth()
                    } label: {
                        ActionRowLabel(title: "重設為本月", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("transactionFilter.thisMonth")
                }
                .calendarDayTimeZone()

                // 類型只有 3 個選項:內嵌選擇列，點一下就選(ADR-0004、#91)。
                Section("類型") {
                    InlineChoiceRows(
                        [(TransactionsModel.TypeFilter.all, "全部類型"), (.expense, "僅支出"), (.income, "僅收入")],
                        selection: $model.filterDraft.type
                    )
                }

                // 帳戶與分類(含「全部帳戶」「全部分類」)的選項多:推入清單頁，選了自動返回。
                // 帳戶的選項隨視角連動(上游 ADR 0019 §3);視角改變時原帳戶不在範圍就重設。
                Section {
                    Picker("帳戶", selection: $model.filterDraft.account) {
                        Text("全部帳戶").tag(AccountChoice?.none)
                        ForEach(model.filterAccountOptions, id: \.self) { account in
                            Text(account.name).tag(Optional(account))
                        }
                    }
                    .navigationLinkStyle()
                    .accessibilityIdentifier("transactionFilter.account")
                    Picker("分類", selection: $model.filterDraft.category) {
                        Text("全部分類").tag(TransactionCategory?.none)
                        ForEach(model.filterDraft.categoryOptions, id: \.self) { category in
                            Label(category.name, systemImage: category.symbolName).tag(Optional(category))
                        }
                    }
                    .navigationLinkStyle()
                    .accessibilityIdentifier("transactionFilter.category")
                }
            }
            .task(id: model.filterDraft.scope) { await model.refreshFilterAccountOptions() }
            .navigationTitle("篩選")
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { model.cancelFilter() }
                SheetConfirmButton("完成", identifier: "transactionFilter.done") {
                    Task { await model.applyFilter() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// DatePicker 用 `Date`;轉換一律以台灣時間計算。
    private func day(_ keyPath: WritableKeyPath<TransactionsModel.Filter, CalendarDay>) -> Binding<Date> {
        Binding(
            get: { model.filterDraft[keyPath: keyPath].startOfDay },
            set: { model.filterDraft[keyPath: keyPath] = CalendarDay(date: $0) }
        )
    }
}
