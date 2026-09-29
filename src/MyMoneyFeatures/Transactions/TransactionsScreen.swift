import Foundation
import MyMoneyDomain
import SwiftUI

/// 「交易」tab:起迄日、視角、篩選、加總列、依日期分組的交易記錄(parity.md「交易」)。
struct TransactionsScreen: View {
    @Bindable var model: TransactionsModel
    let quickEntry: QuickEntryModel
    @State private var isEntryPresented = false
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: MyMoneyDomain.Transaction?

    var body: some View {
        NavigationStack {
            content
                .skeletonTransition(value: model.phase)
                .navigationTitle("交易")
                // 搜尋欄一直顯示在標題下方。iOS 26 起在 TabView 裡用預設位置時，CI 的 UI 階層裡找不到搜尋欄。
                #if os(iOS)
                .searchable(text: $model.keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋備註、分類、帳戶或記帳人")
                #else
                .searchable(text: $model.keyword, prompt: "搜尋備註、分類、帳戶或記帳人")
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isEntryPresented = true
                        } label: {
                            Label("記一筆", systemImage: "plus")
                        }
                        .accessibilityIdentifier("transactions.add")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        ShareLink(
                            item: model.csvExport(),
                            preview: SharePreview("交易記錄 CSV", image: Image(systemName: "tablecells"))
                        ) {
                            Label("匯出 CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                // 起迄日、視角或資料版本任一改變就重抓;類型、分類、關鍵字只在本機過濾。
                .task(id: QueryKey(from: model.from, to: model.to, scope: model.scope, version: model.dataVersion.value)) {
                    await model.load()
                }
                .sheet(isPresented: $isEntryPresented) {
                    TransactionFormView(model: quickEntry)
                }
                .sheet(item: $editor) { sheet in
                    TransactionFormView(model: sheet.model)
                }
                .confirmationDialog(
                    "刪除交易記錄",
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { transaction in
                    Button("刪除", role: .destructive) {
                        Task { await model.delete(transaction) }
                    }
                    Button("取消", role: .cancel) {}
                } message: { _ in
                    Text(model.deleteConfirmation)
                }
                .alert(
                    "無法刪除",
                    isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
                ) {
                    Button("好") {}
                } message: {
                    Text(model.alertMessage ?? "")
                }
        }
    }

    private struct QueryKey: Equatable {
        let from: CalendarDay
        let to: CalendarDay
        let scope: ViewScope
        let version: Int
    }

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: TransactionEditorModel
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                Picker("視角", selection: $model.scope) {
                    Text("全部").tag(ViewScope.all)
                    Text("家庭").tag(ViewScope.household)
                    Text("個人").tag(ViewScope.personal)
                }
                .pickerStyle(.segmented)
                DatePicker("起日", selection: dayBinding(\.from), displayedComponents: .date)
                    .calendarDayTimeZone()
                DatePicker("迄日", selection: dayBinding(\.to), displayedComponents: .date)
                    .calendarDayTimeZone()
                Picker("類型", selection: $model.typeFilter) {
                    Text("全部類型").tag(TransactionsModel.TypeFilter.all)
                    Text("僅支出").tag(TransactionsModel.TypeFilter.expense)
                    Text("僅收入").tag(TransactionsModel.TypeFilter.income)
                }
                Picker("分類", selection: $model.categoryFilter) {
                    Text("全部分類").tag(TransactionCategory?.none)
                    ForEach(model.categoryOptions, id: \.self) { category in
                        Label(category.name, systemImage: category.symbolName).tag(Optional(category))
                    }
                }
            }

            switch model.phase {
            case .loading:
                SkeletonSection(count: 1, announces: true) { SkeletonItemRow() }
                SkeletonSection(count: 3) { TransactionRow(transaction: Skeleton.transaction) }
                SkeletonSection(count: 2) { TransactionRow(transaction: Skeleton.transaction) }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            case .loaded:
                totalsSection
                if model.days.isEmpty {
                    ContentUnavailableView {
                        Label("沒有符合條件的交易記錄", systemImage: "magnifyingglass")
                    } actions: {
                        Button("記一筆") { isEntryPresented = true }
                    }
                }
                ForEach(model.days) { day in
                    Section {
                        ForEach(day.transactions) { transaction in
                            row(transaction)
                        }
                    } header: {
                        DayHeader(day: day)
                    }
                }
            }
        }
        .refreshable { await model.load() }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認)。系統紀錄只顯示鎖定標記。
    @ViewBuilder
    private func row(_ transaction: MyMoneyDomain.Transaction) -> some View {
        if model.canModify(transaction) {
            Button {
                if let editorModel = model.makeEditor(for: transaction) {
                    editor = EditorSheet(model: editorModel)
                }
            } label: {
                TransactionRow(transaction: transaction, recorder: model.recorderName(of: transaction), isOpenable: true)
            }
            .tint(.primary)
            .swipeActions {
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = transaction
                }
            }
            .contextMenu {
                Button("編輯", systemImage: "pencil") {
                    if let editorModel = model.makeEditor(for: transaction) {
                        editor = EditorSheet(model: editorModel)
                    }
                }
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = transaction
                }
            }
        } else {
            // 只放鎖定標記，不放說明文字(#63);點不開，所以不截斷。
            TransactionRow(transaction: transaction, recorder: model.recorderName(of: transaction), isLocked: true)
        }
    }

    private var totalsSection: some View {
        Section {
            HStack {
                Text("\(model.count) 筆")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("總收入 +\(model.totalIncome.formatted())")
                        .foregroundStyle(.green)
                    Text("總支出 -\(model.totalExpense.formatted())")
                        .foregroundStyle(.red)
                    Text("淨收支 \(model.net.formatted())")
                        .bold()
                }
                .font(.subheadline)
                .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(model.count) 筆，總收入 \(model.totalIncome.spokenText),總支出 \(model.totalExpense.spokenText),淨收支 \(model.net.spokenText)"
            )
        }
    }

    /// DatePicker 用 `Date`;轉換一律以台灣時間計算。
    private func dayBinding(_ keyPath: ReferenceWritableKeyPath<TransactionsModel, CalendarDay>) -> Binding<Date> {
        Binding(
            get: { model[keyPath: keyPath].startOfDay },
            set: { model[keyPath: keyPath] = CalendarDay(date: $0) }
        )
    }
}

/// 每天的標頭：日期(「9月29日週二」,DESIGN.md「日期」),以及大於 0 的當日收入與支出。
/// 放不下時(大字級)改成上下堆疊，金額一律單行(DESIGN.md「列與欄位」)。
private struct DayHeader: View {
    let day: TransactionDay

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(day.title)
                Spacer(minLength: 8)
                amounts
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                amounts
            }
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private var amounts: some View {
        if day.income > .zero {
            Text("+\(day.income.formatted())")
                .lineLimit(1)
                .fixedSize()
        }
        if day.expense > .zero {
            Text("-\(day.expense.formatted())")
                .lineLimit(1)
                .fixedSize()
        }
    }
}
