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
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
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
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = model.summary {
            Section {
                SummaryRow(
                    title: "淨可用資產",
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
                        .font(.footnote)
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
                    Text("尚未建立帳戶")
                        .font(.headline)
                    Text("先新增現金錢包、銀行存款帳戶或信用卡，才能開始記帳。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("立即新增") { show(.accounts) }
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
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(card.billedDebt.formatted())
                            .monospacedDigit()
                        Text(cardDetail(card))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    accountLabel(card.name, kind: "信用卡", symbol: "creditcard", colorHex: card.colorHex)
                }
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

    /// 例如「未出帳金額 $3,500 · 繳款日每月 5 號」。
    private func cardDetail(_ card: CreditCard) -> String {
        let unbilled = "未出帳金額 \(card.unbilledDebt.formatted())"
        guard let day = card.paymentDueDay else { return unbilled }
        return "\(unbilled) · 繳款日每月 \(day) 號"
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
                            .font(.footnote)
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
                .font(.footnote)
                .textCase(nil)
        }
    }
}
