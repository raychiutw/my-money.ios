import Foundation
import MyMoneyDomain
import SwiftUI

/// 「總覽」tab(parity.md「總覽」)。最上面是大數字、組成一行與走勢圖,下面是三格數字(各帶兩行組成明細)、超支提示、
/// 功能入口格與帳戶卡片(#116、#117、#178)。toolbar 有視角的篩選按鈕(目前的選擇由按鈕的圖示狀態表達)、記一筆和頭像按鈕。
struct OverviewScreen: View {
    @Bindable var model: OverviewModel
    let quickEntry: QuickEntryModel
    /// 點帳戶卡:帶入該帳戶的篩選再切到記帳頁(#190)。
    let transactions: TransactionsModel
    /// 規劃的三個畫面(週期收支、儲蓄目標、現金流預測)從功能入口 push(#178;原本在「我的」的「規劃」分頁)。
    let recurring: RecurringModel
    let goals: SavingsGoalsModel
    let forecast: ForecastModel
    /// 入口與「管理帳戶」切到其他 tab。
    let show: (AppTab) -> Void

    @Environment(AppSession.self) private var session
    @State private var isEntryPresented = false
    /// 在總覽的導覽堆疊 push 的畫面。入口不是 `NavigationLink`:列表裡的連結會多一個箭頭。
    @State private var path: [OverviewRoute] = []

    private enum OverviewRoute: Hashable {
        case recurring
        case goals
        case forecast
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            // 規劃的三個畫面:model 由 composition root 建立,這裡只負責路由。
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case .recurring: RecurringScreen(model: recurring)
                case .goals: SavingsGoalsScreen(model: goals)
                case .forecast: ForecastScreen(model: forecast)
                }
            }
            .sheet(isPresented: $isEntryPresented) {
                TransactionFormView(model: quickEntry)
            }
            .alert(
                "無法更新已繳狀態",
                isPresented: Binding(get: { model.settleError != nil }, set: { if !$0 { model.clearSettleError() } })
            ) {
                Button("好") {}
            } message: {
                Text(model.settleError ?? "")
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
            entriesSection
            upcomingSection
            accountsSection
        }
    }

    /// 主視覺(#116):超大的淨可用餘額、它的組成一行(#178)加 30 天走勢線;下面是三格數字磚(#117),每格帶兩行組成明細(#178)。
    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                OverviewHero(
                    balance: summary.availableBalance, compositionParts: model.compositionParts,
                    compositionSpoken: model.compositionSpokenText, trend: model.forecastTrend, trendSummary: model.forecastSummary
                )
                .clearListRow()
            }
            .compactSectionSpacing()
            Section {
                NumberTileRow {
                    ForEach(model.summaryTiles) { tile in
                        NumberTile(
                            title: tile.title, amount: tile.amount, text: tile.text, style: tile.tone.color, spokenTitle: tile.spokenTitle,
                            details: tile.details, spokenDetails: tile.spokenDetails
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

    /// 帳戶卡片(#117、#190):橫向捲動的一排，每張是類型圖示加名稱、大金額，底下小字(信用卡兩行:代墊與私帳、未出帳與繳款日);
    /// 最多 `accountCardLimit` 張，其餘用「管理」到帳戶頁。點了切到記帳頁並帶入該帳戶的篩選(信用卡的詳細頁在帳戶頁)。
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
                OverviewAccountCardRow {
                    ForEach(model.accountCards) { card in
                        Button { openTransactions(of: card) } label: {
                            OverviewAccountCardView(card: card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(card.spokenText)
                        .accessibilityHint("查看這個帳戶的\(Terms.transactions)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("overview.card.\(card.id.rawValue)")
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

    /// 點帳戶卡:記帳頁以該帳戶的篩選重新載入，同時切過去。
    private func openTransactions(of card: OverviewAccountCard) {
        Task { await transactions.showAccount(card.choice) }
        show(.transactions)
    }

    /// 功能入口(#178):兩欄的入口格(名稱放不下就單欄),每格圖示加名稱加一個關鍵數字,點了進該功能。
    /// 每格是一個按鈕,VoiceOver 念「名稱,關鍵數字」;失敗或還沒有的數字只是不顯示,不影響其他格。
    private var entriesSection: some View {
        Section {
            OverviewEntryGrid {
                ForEach(model.entries) { entry in
                    Button { open(entry) } label: {
                        OverviewEntryCard(title: entry.title, symbolName: entry.symbolName, value: entry.value, isWarning: entry.isWarning)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.spokenText)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("home.entry.\(entry.destination.rawValue)")
                }
            }
            .clearListRow()
        } header: {
            Text("功能")
        }
    }

    private func open(_ entry: OverviewEntry) {
        switch entry.destination {
        case .recurring: path.append(.recurring)
        case .goals: path.append(.goals)
        case .forecast: path.append(.forecast)
        }
    }

    /// 接下來 30 天(#189):後端預測最近的幾筆預定收支,每筆右邊有「已繳」圓圈(跟現金流預測頁是同一個功能);
    /// 預測載入失敗(或沒有預定收支)時整區不出現,其他照常。區塊標題右邊的「…」到現金流預測。
    @ViewBuilder
    private var upcomingSection: some View {
        if !model.upcomingEvents.isEmpty {
            Section {
                ForEach(model.upcomingEvents) { row in
                    UpcomingEventRow(row: row, isBusy: row.event.key.map(model.settlingKeys.contains) ?? false) {
                        Task { await model.setSettled(!row.event.isSettled, for: row.event) }
                    }
                }
            } header: {
                header("接下來 30 天") {
                    MoreMenu(label: "預定收支的更多動作", identifier: "overview.upcoming.more") {
                        Button("現金流預測", systemImage: "chart.line.uptrend.xyaxis") { path.append(.forecast) }
                    }
                }
            }
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

/// 首次載入的骨架屏:跟載入後一樣的主視覺(大數字與走勢圖)、三格數字磚、功能入口格、接下來 30 天和帳戶卡片。
private struct OverviewSkeleton: View {
    var body: some View {
        Section {
            OverviewHeroSkeleton()
                .clearListRow()
        }
        Section {
            NumberTileRow {
                ForEach(0..<3, id: \.self) { _ in
                    NumberTile(title: "摘要數字", amount: Skeleton.amount, details: ["組成明細", "組成明細"])
                }
            }
            .clearListRow()
            .skeletonRow()
        }
        Section {
            OverviewEntryGrid {
                ForEach(0..<8, id: \.self) { _ in
                    OverviewEntryCard(title: "功能名稱", symbolName: "circle", value: "關鍵數字")
                }
            }
            .clearListRow()
            .skeletonRow()
        } header: {
            SkeletonHeader("功能")
        }
        Section {
            ForEach(0..<2, id: \.self) { _ in
                UpcomingEventRow(row: Skeleton.upcomingEvent, isBusy: false) {}
                    .skeletonRow()
            }
        } header: {
            SkeletonHeader("接下來 30 天")
        }
        Section {
            OverviewAccountCardRow {
                ForEach(0..<3, id: \.self) { _ in
                    OverviewAccountCardView(card: Skeleton.accountCard)
                }
            }
            .clearListRow()
            .skeletonRow()
        } header: {
            SkeletonHeader("帳戶")
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
