import Foundation
import MyMoneyDomain
import SwiftUI

/// 「總覽」tab(parity.md「總覽」)。最上面是大數字、組成一行與走勢圖,下面是三格數字(各帶兩行組成明細)、超支提示、
/// 功能入口格與帳戶卡片(#116、#117、#178)。toolbar 有視角的篩選按鈕(目前的選擇由按鈕的圖示狀態表達)、記一筆和頭像按鈕。
struct OverviewScreen: View {
    @Bindable var model: OverviewModel
    let quickEntry: QuickEntryModel
    /// 規劃的三個畫面(週期收支、儲蓄目標、現金流預測)從功能入口 push(#178;原本在「我的」的「規劃」分頁)。
    let recurring: RecurringModel
    let goals: SavingsGoalsModel
    let forecast: ForecastModel
    /// 入口與「管理帳戶」切到其他 tab。
    let show: (AppTab) -> Void

    @Environment(AppSession.self) private var session
    @State private var isEntryPresented = false
    /// 在總覽的導覽堆疊 push 的畫面。信用卡卡片和入口都不是 `NavigationLink`:列表裡的連結會多一個箭頭。
    @State private var path: [OverviewRoute] = []

    private enum OverviewRoute: Hashable {
        case card(CreditCard)
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
            // 帳戶一覽的信用卡精簡列點進信用卡詳細頁;詳細頁的 model 由這裡(路由)建立(#73)。
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case .card(let card): CreditCardDetailScreen(model: model.makeCardDetail(for: card))
                case .recurring: RecurringScreen(model: recurring)
                case .goals: SavingsGoalsScreen(model: goals)
                case .forecast: ForecastScreen(model: forecast)
                }
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
            entriesSection
            accountsSection
        }
    }

    /// 主視覺(#116):超大的淨可用餘額、它的組成一行(#178)加 30 天走勢線;下面是三格數字磚(#117),每格帶兩行組成明細(#178)。
    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                OverviewHero(
                    balance: summary.availableBalance, composition: model.compositionText,
                    compositionSpoken: model.compositionSpokenText, trend: model.forecastTrend, trendSummary: model.forecastSummary
                )
                .clearListRow()
            }
            .compactSectionSpacing()
            Section {
                NumberTileRow {
                    ForEach(model.summaryTiles) { tile in
                        NumberTile(
                            title: tile.title, amount: tile.amount, style: tile.isWarning ? .red : nil, spokenTitle: tile.spokenTitle,
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
            Button { path.append(.card(creditCard)) } label: { view }
                .buttonStyle(.plain)
                .accessibilityIdentifier("overview.card.\(card.id.rawValue)")
        } else {
            view
        }
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
        case .ledger: show(.transactions)
        case .accounts, .creditCards: show(.accounts)
        case .household: show(.household)
        case .statistics: show(.statistics)
        case .recurring: path.append(.recurring)
        case .goals: path.append(.goals)
        case .forecast: path.append(.forecast)
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

/// 首次載入的骨架屏:跟載入後一樣的主視覺(大數字與走勢圖)、三格數字磚、功能入口格和帳戶卡片。
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
