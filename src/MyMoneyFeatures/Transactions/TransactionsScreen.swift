import Foundation
import MyMoneyDomain
import SwiftUI

/// 「交易」tab:搜尋、數字優先的主視覺(淨收支、比例條、每日支出長條圖)、依日期分組的交易記錄(parity.md「交易」,#118)。
///
/// 視角、起迄日、類型、分類收在 toolbar 篩選按鈕打開的「篩選」sheet(#74),目前的範圍是篩選按鈕的 VoiceOver 值;
/// toolbar 只有篩選、記一筆和頭像三顆,匯出 CSV 是列表最底下的一列(ADR-0004);
/// 打開畫面最上面就是主視覺和交易記錄。
struct TransactionsScreen: View {
    @Bindable var model: TransactionsModel
    let quickEntry: QuickEntryModel
    @State private var isEntryPresented = false
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: MyMoneyDomain.Transaction?
    /// 點了點不開的列:跳出簡短說明(#146)。
    @State private var explained: MyMoneyDomain.Transaction?

    var body: some View {
        NavigationStack {
            content
                .skeletonTransition(value: model.phase)
                .tabRootNavigation("交易")
                // 搜尋欄一直顯示在標題下方。iOS 26 起在 TabView 裡用預設位置時，CI 的 UI 階層裡找不到搜尋欄。
                #if os(iOS)
                .searchable(text: $model.keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋備註、分類、帳戶或記帳人")
                #else
                .searchable(text: $model.keyword, prompt: "搜尋備註、分類、帳戶或記帳人")
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        // 跟其他頁的篩選按鈕(`ScopeFilter`)同一個 symbol。label 用 `Label` 時,toolbar 上的
                        // `accessibilityValue` 會被丟掉，所以只放 symbol,標籤另外用 `accessibilityLabel` 補上。
                        Button {
                            model.editFilter()
                        } label: {
                            FilterIconImage(isActive: model.isFilterActive)
                        }
                        .accessibilityLabel("篩選")
                        .accessibilityValue(model.filterSummary)
                        .accessibilityIdentifier("transactions.filter")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isEntryPresented = true
                        } label: {
                            Label("記一筆", systemImage: "plus")
                        }
                        .accessibilityIdentifier("transactions.add")
                    }
                    AccountToolbarItem()
                }
                // 資料版本改變就重抓。篩選改了由 sheet 的「完成」查詢(只查詢一次),這裡不跟著篩選重抓。
                .task(id: model.dataVersion.value) {
                    await model.load()
                }
                .sheet(isPresented: $model.isEditingFilter) {
                    TransactionFilterView(model: model)
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
                    model.lockAlertTitle,
                    isPresented: Binding(get: { explained != nil }, set: { if !$0 { explained = nil } }),
                    presenting: explained
                ) { _ in
                    Button("好") {}
                } message: { transaction in
                    Text("\(model.lockReason(for: transaction) ?? "")。")
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

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: TransactionEditorModel
    }

    @ViewBuilder
    private var content: some View {
        List {
            // 年月快速切換:不論載入狀態都在最上面(載入失敗時也能換個月再試)。
            Section {
                MonthPill(model: model)
                    .clearListRow()
            }
            .compactSectionSpacing()
            switch model.phase {
            case .loading:
                Section {
                    TransactionsHeroSkeleton()
                        .clearListRow()
                }
                SkeletonSection(count: 3) { TransactionRow(transaction: Skeleton.transaction) }
                SkeletonSection(count: 2) { TransactionRow(transaction: Skeleton.transaction) }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            case .loaded:
                Section {
                    TransactionsHero(model: model)
                        .clearListRow()
                }
                let days = model.days
                if days.isEmpty {
                    ContentUnavailableView {
                        Label("沒有符合條件的交易記錄", systemImage: "magnifyingglass")
                    } actions: {
                        Button("記一筆") { isEntryPresented = true }
                    }
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.transactions) { transaction in
                            row(transaction)
                        }
                    } header: {
                        // 筆數寫在交易記錄的標題，放在第一天的標頭上面(#74);用粗一級的字，跟日期分得開。
                        if day.id == days.first?.id {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("交易記錄(\(model.count))")
                                    .font(.headline)
                                DayHeader(day: day)
                            }
                        } else {
                            DayHeader(day: day)
                        }
                    }
                }
                exportSection
            }
        }
        .refreshable { await model.load() }
    }

    /// 匯出 CSV:列表最底下的一列(ADR-0004、#86),匯出目前篩選範圍的交易記錄。
    /// 沒有交易記錄時也照樣顯示，跟以前工具列上的匯出按鈕一樣。
    private var exportSection: some View {
        Section {
            ShareLink(
                item: model.csvExport(),
                preview: SharePreview("交易記錄 CSV", image: Image(systemName: "tablecells"))
            ) {
                Label("匯出 CSV", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("transactions.export")
        }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認)。系統紀錄與沒有權限的他人交易(#133)點不開。
    @ViewBuilder
    private func row(_ transaction: MyMoneyDomain.Transaction) -> some View {
        if model.canModify(transaction) {
            Button {
                if let editorModel = model.makeEditor(for: transaction) {
                    editor = EditorSheet(model: editorModel)
                }
            } label: {
                TransactionRow(
                    transaction: transaction, subtitle: model.subtitle(of: transaction),
                    recorder: model.recorderName(of: transaction), isOpenable: true
                )
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
            // 列上沒有鎖定標記(#145);點一下跳出簡短說明(#146)。沒有左滑刪除與長按選單。點不開，所以標題不截斷。
            Button {
                explained = transaction
            } label: {
                TransactionRow(
                    transaction: transaction, subtitle: model.subtitle(of: transaction),
                    recorder: model.recorderName(of: transaction), lockHint: model.lockHint(for: transaction)
                )
            }
            .tint(.primary)
        }
    }
}

/// 每天的標頭：日期(「9月29日週二」,DESIGN.md「日期」)，以及當日淨額(帶正負號;只有系統分類的那天沒有，#118)。
/// 放不下時(大字級)改成上下堆疊，金額一律單行(DESIGN.md「列與欄位」)。
private struct DayHeader: View {
    let day: TransactionDay

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(day.title)
                Spacer(minLength: 8)
                net
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                net
            }
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private var net: some View {
        if day.hasNet {
            Text(day.netText)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(day.net > .zero ? Color.green : (day.net < .zero ? Color.red : Color.secondary))
                .accessibilityLabel("當日淨額 \(day.net.spokenText)")
        }
    }
}

/// 主視覺的骨架屏:跟載入後一樣的大數字與灰色圖表區塊。
private struct TransactionsHeroSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BigNumber(title: "淨收支", amount: Skeleton.amount)
            SkeletonChart(height: 110)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .skeletonAnnouncement()
    }
}
