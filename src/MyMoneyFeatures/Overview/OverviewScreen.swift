import Foundation
import MyMoneyDomain
import SwiftUI

/// 「總覽」tab(parity.md「總覽」)。toolbar 有視角的篩選按鈕(目前的選擇顯示在導覽列副標題)、記一筆和頭像按鈕。
struct OverviewScreen: View {
    @Bindable var model: OverviewModel
    let quickEntry: QuickEntryModel
    /// 「管理帳戶」「查看全部」切到其他 tab。
    let show: (AppTab) -> Void

    @Environment(AppSession.self) private var session
    @State private var isEntryPresented = false

    var body: some View {
        NavigationStack {
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
                    Button("重試") {
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
            goalsSection
        }
    }

    /// 主視覺(#116):超大的淨可用餘額加 30 天走勢線;下面的摘要是真實可支配現金、當月淨收支。
    /// 公式明細不寫：淨可用餘額的組成在帳戶頁，分攤平滑與每月預留在週期收支、儲蓄目標頁，當月收入與支出在統計頁。
    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                OverviewHero(
                    balance: summary.availableBalance, trend: model.forecastTrend, trendSummary: model.forecastSummary
                )
            }
            Section {
                AmountRow(title: "真實可支配現金", amount: summary.disposableCash, warnsWhenNegative: true)
                AmountRow(title: model.netTitle, amount: model.monthNet, warnsWhenNegative: true)
            }
        }
    }

    /// 超支警告(#75):標題是「有 N 個分類支出已超出預算」,每個超支的分類一列，顯示分類名稱和超支金額。
    /// 已花和預算額度在統計頁的預算額度。
    private var overBudgetSection: some View {
        Section {
            ForEach(model.overBudgets) { item in
                LabeledContent {
                    Text("超支 \(item.overspent.formatted())")
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                } label: {
                    Label(item.category.name, systemImage: item.category.symbolName)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.category.name)
                .accessibilityValue("超支 \(item.overspent.spokenText)")
            }
        } header: {
            Label(model.overBudgetTitle, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textCase(nil)
        }
    }

    private var accountsSection: some View {
        Section {
            if model.cashWallets.isEmpty && model.bankAccounts.isEmpty && model.creditCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.scope.accountScope.emptyAccountsTitle)
                        .font(.headline)
                    Text(model.scope.accountScope.emptyAccountsHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("前往帳戶管理") { show(.accounts) }
                        .buttonStyle(.borderless)
                }
            }
            ForEach(model.cashWallets) { wallet in
                LabeledContent {
                    Text(wallet.balance.formatted())
                        .monospacedDigit()
                } label: {
                    accountLabel(wallet.name, kind: "現金錢包", symbol: "wallet.bifold", colorHex: wallet.colorHex)
                }
            }
            ForEach(model.bankAccounts) { account in
                LabeledContent {
                    Text(account.balance.formatted())
                        .monospacedDigit()
                } label: {
                    accountLabel(account.name, kind: "銀行存款帳戶", symbol: "building.columns", colorHex: account.colorHex)
                }
            }
            // 信用卡跟帳戶頁用同一種精簡列，點進信用卡詳細頁(#73)。
            ForEach(model.creditCards) { card in
                NavigationLink(value: card) {
                    CreditCardSummaryRow(card: card, mark: .symbol)
                }
                .accessibilityIdentifier("overview.card.\(card.id.rawValue)")
            }
        } header: {
            header("帳戶一覽", action: "管理帳戶") { show(.accounts) }
        }
    }

    /// 名稱、類型(symbol)和使用者選的代表色;VoiceOver 念類型的名稱，不念 symbol。
    private func accountLabel(_ name: String, kind: String, symbol: String, colorHex: String) -> some View {
        Label {
            Text(name)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color(hex: colorHex) ?? .gray)
                .accessibilityLabel(kind)
        }
    }

    private var recentSection: some View {
        Section {
            if model.recentTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("此視角目前尚無交易")
                        .foregroundStyle(.secondary)
                    Button("記一筆") { isEntryPresented = true }
                        .buttonStyle(.borderless)
                }
            }
            // 總覽的列點不開，所以不截斷;也沒有編輯，所以不放系統紀錄的鎖定標記。
            ForEach(model.recentTransactions) { transaction in
                TransactionRow(
                    transaction: transaction, recorder: model.recorderName(of: transaction),
                    date: model.dateText(of: transaction)
                )
            }
        } header: {
            header("最近交易", action: "查看全部") { show(.transactions) }
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        Section {
            if model.topGoals.isEmpty {
                Text("尚未設立任何儲蓄目標")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.topGoals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(goal.emoji) \(goal.name)")
                        Spacer()
                        Text("\(goal.savedAmount.formatted()) / \(goal.targetAmount.formatted())")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    // 達成時用成功色(parity 刻意偏離第 6 項)。
                    ProgressView(value: goal.progress)
                        .tint(goal.isAchieved ? .green : .accentColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(goal.name),已存 \(goal.savedAmount.spokenText),目標 \(goal.targetAmount.spokenText),\(goal.percentText)\(goal.isAchieved ? ",已達成目標" : "")"
                )
            }
        } header: {
            Text("儲蓄目標")
        }
    }

    private func header(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action, action: perform)
                .font(.subheadline)
                .textCase(nil)
        }
    }
}

/// 首次載入的骨架屏：跟載入後一樣的主視覺(大數字與走勢圖)、摘要兩列、帳戶一覽、最近交易和儲蓄目標。
private struct OverviewSkeleton: View {
    var body: some View {
        Section {
            OverviewHeroSkeleton()
        }
        Section {
            ForEach(0..<2, id: \.self) { _ in
                AmountRow(title: "摘要數字", amount: Skeleton.amount)
                    .skeletonRow()
            }
        }
        Section {
            ForEach(0..<3, id: \.self) { _ in
                LabeledContent {
                    Text(Skeleton.amount.formatted())
                } label: {
                    Label("帳戶名稱", systemImage: "building.columns")
                }
                .skeletonRow()
            }
        } header: {
            SkeletonHeader("帳戶一覽")
        }
        Section {
            ForEach(0..<4, id: \.self) { _ in
                TransactionRow(transaction: Skeleton.transaction)
                    .skeletonRow()
            }
        } header: {
            SkeletonHeader("最近交易")
        }
        Section {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("儲蓄目標名稱")
                        Spacer()
                        Text("\(Skeleton.amount.formatted()) / \(Skeleton.amount.formatted())")
                            .font(.footnote)
                    }
                    ProgressView(value: 0.4)
                }
                .skeletonRow()
            }
        } header: {
            SkeletonHeader("儲蓄目標")
        }
    }
}
