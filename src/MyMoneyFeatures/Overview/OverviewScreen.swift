import Foundation
import MyMoneyDomain
import SwiftUI

/// 「總覽」tab(parity.md「總覽」)。toolbar 有記一筆和帳號 sheet。
struct OverviewScreen: View {
    @Bindable var model: OverviewModel
    let quickEntry: QuickEntryModel
    /// 帳號 sheet 裡的「家庭」。
    let household: HouseholdModel
    /// 帳號 sheet 裡的「機器人記帳」。
    let bot: BotModel
    /// 「管理帳戶」「查看全部」切到其他 tab。
    let show: (AppTab) -> Void

    @Environment(AppSession.self) private var session
    @State private var isEntryPresented = false
    @State private var isAccountSheetPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("視角", selection: $model.scope) {
                        Text("全部").tag(ViewScope.all)
                        Text("家庭").tag(ViewScope.household)
                        Text("個人").tag(ViewScope.personal)
                    }
                    .pickerStyle(.segmented)
                }
                content
            }
            .navigationTitle(greeting)
            .skeletonTransition(value: model.phase)
            .refreshable { await model.load() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEntryPresented = true
                    } label: {
                        Label("記一筆", systemImage: "plus")
                    }
                    .accessibilityIdentifier("overview.add")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAccountSheetPresented = true
                    } label: {
                        Label("帳號", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("overview.account")
                }
            }
            // 視角或資料版本改變就重抓(例如從總覽或交易頁記一筆之後)。
            .task(id: QueryKey(scope: model.scope, version: model.dataVersion.value)) {
                await model.load()
            }
            .sheet(isPresented: $isEntryPresented) {
                TransactionFormView(model: quickEntry)
            }
            .sheet(isPresented: $isAccountSheetPresented) {
                AccountSheet(household: household, bot: bot)
            }
        }
    }

    private struct QueryKey: Equatable {
        let scope: ViewScope
        let version: Int
    }

    /// 依裝置的當地時間問候(parity 刻意偏離第 21 項)。
    private var greeting: String {
        OverviewModel.greeting(hour: Calendar.current.component(.hour, from: .now), name: session.current?.user.name ?? "朋友")
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
            Section("家庭財務錦囊") {
                Label(model.tipText, systemImage: "lightbulb")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                SummaryRow(
                    title: "淨可用餘額",
                    amount: summary.availableBalance,
                    detail: model.availableBreakdown ?? "",
                    warnsWhenNegative: true
                )
                SummaryRow(
                    title: "真實可支配現金",
                    amount: summary.disposableCash,
                    detail: "已扣掉週期攤提 \(summary.monthlyAmortization.formatted()) 與每月預留 \(summary.monthlySavingsReserve.formatted())",
                    warnsWhenNegative: true
                )
                SummaryRow(
                    title: model.netTitle,
                    amount: model.monthNet,
                    detail: "收入 \(model.monthIncome.formatted()) · 支出 \(model.monthExpense.formatted())",
                    warnsWhenNegative: true
                )
            }
        }
    }

    private var overBudgetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(model.overBudgetTitle, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                ForEach(model.overBudgets, id: \.category) { budget in
                    Text("\(budget.category.name):已花 \(budget.spent.formatted()) / 預算 \(budget.amount.formatted())(超支 \((budget.spent - budget.amount).formatted()))")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
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
            ForEach(model.creditCards) { card in
                LabeledContent {
                    // 信用卡待繳總額(已出帳加未出帳),有待繳時用紅色(web 的 Dashboard 在 82d9124 起)。
                    Text(card.totalDue.formatted())
                        .monospacedDigit()
                        .foregroundStyle(card.totalDue > .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                } label: {
                    accountLabel(card.name, kind: "信用卡", symbol: "creditcard", colorHex: card.colorHex, details: OverviewModel.cardDetailLines(card))
                }
            }
        } header: {
            header("帳戶一覽", action: "管理帳戶") { show(.accounts) }
        }
    }

    /// 名稱、類型(symbol)和使用者選的代表色;VoiceOver 念類型的名稱，不念 symbol。`details` 是名稱下面的說明。
    private func accountLabel(_ name: String, kind: String, symbol: String, colorHex: String, details: [String] = []) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
            ForEach(model.recentTransactions) { transaction in
                TransactionRow(transaction: transaction)
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

/// 首次載入的骨架屏：跟載入後一樣的三張統計卡、帳戶一覽、最近交易和儲蓄目標。
private struct OverviewSkeleton: View {
    var body: some View {
        Section {
            SummaryRow(title: "淨可用餘額", amount: Skeleton.amount, detail: Skeleton.text)
                .skeletonAnnouncement()
            ForEach(0..<2, id: \.self) { _ in
                SummaryRow(title: "統計卡", amount: Skeleton.amount, detail: Skeleton.text)
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
