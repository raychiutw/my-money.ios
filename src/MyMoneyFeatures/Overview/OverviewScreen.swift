import Foundation
import MyMoneyDomain
import SwiftUI

/// 「總覽」tab(parity.md「總覽」)。最上面是大數字與走勢圖，下面是數字磚、帳戶卡片、最近交易、超支提示與儲蓄目標圓環(#116、#117)。
/// toolbar 有視角的篩選按鈕(目前的選擇由按鈕的圖示狀態表達)、記一筆和頭像按鈕。
struct OverviewScreen: View {
    @Bindable var model: OverviewModel
    let quickEntry: QuickEntryModel
    /// 「管理帳戶」「查看全部」切到其他 tab。
    let show: (AppTab) -> Void

    @Environment(AppSession.self) private var session
    @State private var isEntryPresented = false
    /// 點帳戶卡片上的信用卡 push 信用卡詳細頁。卡片不是 `NavigationLink`:列表裡的連結會多一個箭頭。
    @State private var cardPath: [CreditCard] = []

    var body: some View {
        NavigationStack(path: $cardPath) {
            List {
                content
            }
            .tabRootNavigation("總覽")
            .skeletonTransition(value: model.phase)
            .refreshable { await model.load() }
            .toolbar {
                ScopeFilter("視角", scope: $model.scope, identifier: "overview.scope")
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEntryPresented = true
                    } label: {
                        Label("記一筆", systemImage: "plus")
                    }
                    .accessibilityIdentifier("overview.add")
                }
                AccountToolbarItem()
            }
            // 視角或資料版本改變就重抓(例如從總覽或交易頁記一筆之後);從信用卡詳細頁返回時 task 會重跑，沒變就不重抓。
            .task(id: QueryKey(scope: model.scope, version: model.dataVersion.value)) {
                await model.refreshIfStale()
            }
            // 帳戶一覽的信用卡精簡列點進信用卡詳細頁;詳細頁的 model 由這裡(路由)建立(#73)。
            .navigationDestination(for: CreditCard.self) { card in
                CreditCardDetailScreen(model: model.makeCardDetail(for: card))
            }
            .sheet(isPresented: $isEntryPresented) {
                TransactionFormView(model: quickEntry)
            }
        }
    }

    private struct QueryKey: Equatable {
        let scope: ViewScope
        let version: Int
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            OverviewSkeleton()
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("無法載入總覽", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    GlassCapsuleButton(title: "重試") {
                        Task { await model.load() }
                    }
                }
            }
        case .loaded:
            summarySection
            if !model.overBudgets.isEmpty {
                overBudgetSection
            }
            accountsSection
            recentSection
            if !model.topGoals.isEmpty {
                goalsSection
            }
        }
    }

    /// 主視覺(#116):超大的淨可用餘額加 30 天走勢線;下面是三格數字磚(#117)。
    /// 公式明細不寫：淨可用餘額的組成在帳戶頁，分攤平滑與每月預留在週期收支、儲蓄目標頁，當月收入與支出在統計頁。
    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                OverviewHero(
                    balance: summary.availableBalance, trend: model.forecastTrend, trendSummary: model.forecastSummary
                )
                .clearListRow()
            }
            .compactSectionSpacing()
            Section {
                NumberTileRow {
                    ForEach(model.summaryTiles) { tile in
                        NumberTile(
                            title: tile.title, amount: tile.amount, style: tile.isWarning ? .red : nil, spokenTitle: tile.spokenTitle
                        )
                    }
                }
                .clearListRow()
            }
            .compactSectionSpacing()
        }
    }

    /// 超支提示(#117):精簡的紅色提示「N 個分類超支」，點了切到統計 tab 的預算額度。
    private var overBudgetSection: some View {
        Section {
            OverBudgetChip(title: model.overBudgetChipTitle, spokenTitle: model.overBudgetTitle) {
                show(.statistics)
            }
            .accessibilityIdentifier("overview.overBudget")
            .clearListRow()
        }
        .compactSectionSpacing()
    }

    /// 帳戶卡片(#117):兩欄網格(大字級自然變一欄)，每張是名稱加大金額;最多 `accountCardLimit` 張，其餘用「管理」到帳戶頁。
    /// 信用卡的金額是信用卡待繳總額(有待繳時紅色)加「N 日繳」,點了進信用卡詳細頁(#73)。
    private var accountsSection: some View {
        Section {
            if model.accountCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.scope.accountScope.emptyAccountsTitle)
                        .font(.headline)
                    Text(model.scope.accountScope.emptyAccountsHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    GlassCapsuleButton(title: "前往帳戶管理") { show(.accounts) }
                }
            } else {
                NumberCardGrid {
                    ForEach(model.accountCards) { card in
                        accountCard(card)
                    }
                }
                .clearListRow()
            }
        } header: {
            header("帳戶") {
                MoreMenu(label: "帳戶的更多動作", identifier: "overview.accounts.more") {
                    Button("管理帳戶", systemImage: "building.columns") { show(.accounts) }
                }
            }
        }
    }

    @ViewBuilder
    private func accountCard(_ card: OverviewAccountCard) -> some View {
        let view = NumberCard(
            title: card.name, symbol: card.symbolName, symbolColor: Color(hex: card.colorHex) ?? .gray, amount: card.amount,
            isWarning: card.isDue, caption: card.dueDayText, spokenText: card.spokenText
        )
        if case .creditCard(let creditCard) = card.kind {
            Button { cardPath.append(creditCard) } label: { view }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overview.card.\(card.id.rawValue)")
        } else {
            view
        }
    }

    /// 最近交易(#117):只有圖示、名稱和金額，約 5 筆;其他欄位在交易頁。
    private var recentSection: some View {
        Section {
            if model.recentTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("此視角目前尚無\(Terms.transactions)")
                        .foregroundStyle(.secondary)
                    GlassCapsuleButton(title: "記一筆") { isEntryPresented = true }
                }
            }
            ForEach(model.recentTransactions) { transaction in
                CompactTransactionRow(transaction: transaction)
            }
        } header: {
            header("最近") {
                MoreMenu(label: "最近\(Terms.transactions)的更多動作", identifier: "overview.recent.more") {
                    Button("查看全部\(Terms.transactions)", systemImage: "list.bullet") { show(.transactions) }
                    Button("記一筆", systemImage: "plus") { isEntryPresented = true }
                }
            }
        }
    }

    /// 儲蓄目標(#117):最多三個小圓環;沒有目標時整區不出現(由 `content` 判斷)。
    private var goalsSection: some View {
        Section {
            ForEach(model.topGoals) { goal in
                GoalRingRow(goal: goal)
            }
        } header: {
            Text("目標")
        }
    }

    /// 區塊標題:右邊是「…」玻璃圓鈕，點開選單(#134;取代「管理」「全部」這類裸文字按鈕)。
    private func header(_ title: String, @ViewBuilder more: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            more()
                .textCase(nil)
        }
    }
}

/// 首次載入的骨架屏：跟載入後一樣的主視覺(大數字與走勢圖)、三格數字磚、帳戶卡片、最近交易和儲蓄目標圓環。
private struct OverviewSkeleton: View {
    var body: some View {
        Section {
            OverviewHeroSkeleton()
                .clearListRow()
        }
        Section {
            NumberTileRow {
                ForEach(0..<3, id: \.self) { _ in
                    NumberTile(title: "摘要數字", amount: Skeleton.amount)
                }
            }
            .clearListRow()
            .skeletonRow()
        }
        Section {
            NumberCardGrid {
                ForEach(0..<4, id: \.self) { _ in
                    NumberCard(
                        title: "帳戶名稱", symbol: "building.columns", symbolColor: .gray, amount: Skeleton.amount, spokenText: ""
                    )
                }
            }
            .clearListRow()
            .skeletonRow()
        } header: {
            SkeletonHeader("帳戶")
        }
        Section {
            ForEach(0..<4, id: \.self) { _ in
                CompactTransactionRow(transaction: Skeleton.transaction)
                    .skeletonRow()
            }
        } header: {
            SkeletonHeader("最近")
        }
        Section {
            ForEach(0..<2, id: \.self) { _ in
                GoalRingRow(goal: Skeleton.goal)
                    .skeletonRow()
            }
        } header: {
            SkeletonHeader("目標")
        }
    }
}

extension View {
    /// 總覽裡自己畫底色的列(數字磚、卡片網格、提示):列本身沒有底色、沒有分隔線、不縮排，
    /// 內容用滿列表的寬度(列表的左右邊界本來就在外面)。
    func clearListRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
