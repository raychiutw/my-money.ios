import Foundation
import MyMoneyDomain
import SwiftUI

/// 「帳戶」tab:數字優先的主視覺(淨可用餘額、組成比例條、三格數字磚)，
/// 現金錢包、銀行存款帳戶與信用卡帳戶三區的卡片(parity.md「帳戶」,#119)。
/// toolbar 有帳戶檢視範圍的篩選按鈕(目前的選擇由按鈕的圖示狀態表達)、新增資產帳戶和頭像三顆。
/// 每個帳戶是一張卡片(整列):點一下進詳細頁(#73),右上角 ⋯ 是這個帳戶的完整動作清單,往左滑是刪除。
struct AccountsScreen: View {
    @Bindable var model: AccountsModel
    /// 切到別的 tab(待報銷橫幅的「前往家庭」)。
    var showTab: (AppTab) -> Void = { _ in }
    @State private var editor: EditorSheet?
    @State private var skeletonWidth: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingDeletion: Account?
    @State private var rollover: StatementRolloverModel?
    @State private var cardNeedingStatementDay: CreditCard?
    @State private var payment: CardPaymentModel?
    @State private var transfer: TransferModel?
    /// 點帳戶卡片 push 詳細頁(信用卡、現金、活存)。卡片不是 `NavigationLink`:列表裡的連結會多一個箭頭。
    @State private var path: [Account] = []
    @State private var cardToReconcile: CreditCard?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .skeletonTransition(value: model.phase)
                .tabRootNavigation("帳戶")
                .toolbar {
                    ScopeFilter("帳戶檢視範圍", scope: $model.scope, identifier: "accounts.scope")
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("新增\(Terms.cash)", systemImage: "wallet.bifold") {
                                editor = EditorSheet(model.makeEditor(adding: .cash))
                            }
                            Button("新增\(Terms.bankAccount)", systemImage: "building.columns") {
                                editor = EditorSheet(model.makeEditor(adding: .bank))
                            }
                            Button("新增信用卡", systemImage: "creditcard") {
                                editor = EditorSheet(model.makeEditor(adding: .creditCard))
                            }
                        } label: {
                            Label("新增資產帳戶", systemImage: "plus")
                        }
                        .accessibilityIdentifier("accounts.add")
                    }
                    AccountToolbarItem()
                }
                // 第一次出現時載入;之後檢視範圍或資料版本改變(任何畫面新增、修改、刪除成功)就重抓。
                .task(id: model.reloadKey) {
                    await model.refreshIfStale()
                }
                // 詳細頁的 model 由這裡(路由)建立，跟帳戶頁同一個帳戶檢視範圍。
                .navigationDestination(for: Account.self) { account in
                    if case .creditCard(let card) = account {
                        CreditCardDetailScreen(model: model.makeCardDetail(for: card))
                    } else {
                        AccountDetailScreen(model: model.makeAccountDetail(for: account))
                    }
                }
                .sheet(item: $editor) { sheet in
                    AccountEditorView(model: sheet.model)
                }
                .alert(
                    "刪除資產帳戶",
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    presenting: pendingDeletion
                ) { account in
                    Button("刪除", role: .destructive) {
                        Task { await model.delete(account) }
                    }
                    Button("取消", role: .cancel) {}
                } message: { account in
                    Text(model.deleteConfirmation(for: account))
                }
                .sheet(item: $transfer) { transfer in
                    TransferView(model: transfer) { message in model.noticeMessage = message }
                }
                .sheet(item: $payment) { payment in
                    CardPaymentView(model: payment)
                }
                .sheet(item: $rollover) { rollover in
                    StatementRolloverView(model: rollover) { message in model.noticeMessage = message }
                }
                .alert(
                    "無法出帳作業",
                    isPresented: Binding(get: { cardNeedingStatementDay != nil }, set: { if !$0 { cardNeedingStatementDay = nil } }),
                    presenting: cardNeedingStatementDay
                ) { card in
                    Button("前往設定") { editor = EditorSheet(model.makeEditor(editing: .creditCard(card))) }
                    Button("取消", role: .cancel) {}
                } message: { _ in
                    Text(StatementRolloverModel.missingStatementDayMessage)
                }
                .alert(
                    "校準未出帳",
                    isPresented: Binding(get: { cardToReconcile != nil }, set: { if !$0 { cardToReconcile = nil } }),
                    presenting: cardToReconcile
                ) { card in
                    Button("校準") { Task { await model.reconcile(card) } }
                    Button("取消", role: .cancel) {}
                } message: { card in
                    Text(card.reconcileConfirmation)
                }
                .errorAlert("無法完成", message: model.alertMessage) { model.alertMessage = nil }
                .alert(
                    "完成",
                    isPresented: Binding(get: { model.noticeMessage != nil }, set: { if !$0 { model.noticeMessage = nil } })
                ) {
                    Button("好") {}
                } message: {
                    Text(model.noticeMessage ?? "")
                }
        }
    }

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: AccountEditorModel

        init(_ model: AccountEditorModel) {
            self.model = model
        }
    }

    /// 點一下進詳細頁;右上角 ⋯ 是完整動作清單(轉帳、編輯、刪除,信用卡再加繳款、出帳作業、校準);往左滑是刪除(刪除前一律確認：後端刪除無法復原)。
    /// 沒有編輯權限的帳戶(別人建立的家庭共同帳戶，上游 ADR 0013、#133)沒有編輯與刪除，轉帳照舊。
    private func accountRow(_ account: Account, identifier: String? = nil, @ViewBuilder label: () -> some View) -> some View {
        Button {
            path.append(account)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            let items = model.menuItems(for: account)
            if !items.isEmpty {
                MoreMenu(label: "\(account.name)的更多動作", identifier: "accounts.more.\(account.id.rawValue)") {
                    AccountMenuButtons(items: items) { perform($0, on: account) }
                }
            }
        }
        .clearListRow()
        .accessibilityIdentifier(identifier ?? "accounts.row.\(account.id.rawValue)")
        .swipeActions {
            if model.canModify(account) {
                DestructiveSwipeButton { pendingDeletion = account }
            }
        }
    }

    /// ⋯ 選單的每個項目要做的事。
    private func perform(_ item: AccountMenuItem, on account: Account) {
        switch item {
        case .transfer:
            transfer = model.makeTransfer(into: account)
        case .edit:
            editor = EditorSheet(model.makeEditor(editing: account))
        case .delete:
            pendingDeletion = account
        case .pay(let preset):
            if case .creditCard(let card) = account { payment = model.makePayment(for: card, preset: preset) }
        case .rollover:
            guard case .creditCard(let card) = account else { return }
            if model.rolloverNeedsStatementDay(for: card) {
                cardNeedingStatementDay = card
            } else {
                rollover = model.makeStatementRollover(for: card)
            }
        case .reconcile:
            if case .creditCard(let card) = account { cardToReconcile = card }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        BigNumber(title: "淨可用餘額", amount: .plain(Skeleton.amount))
                        SkeletonChart(height: 12)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .skeletonAnnouncement()
                    .clearListRow()
                }
                Section {
                    // 跟著實際版面(#204):磚用上次記下的並排或單欄,佔位字跟真實內容一樣寬;卡片張數用上次的張數。
                    NumberTileRow(forcedSingleColumn: model.skeletonShape.arrangement(forWidth: skeletonWidth, sizeKey: String(describing: dynamicTypeSize), for: "tiles")) {
                        ForEach([Terms.cash, Terms.bankAccount, "信用卡待繳"], id: \.self) { title in
                            NumberTile(title: title, amount: .plain(Skeleton.tileAmount))
                                .skeletonCell("accounts.skeleton.tile.\(title)")
                        }
                    }
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { skeletonWidth = $0 }
                    .clearListRow()
                    .skeletonRow()
                }
                let counts = model.skeletonCounts
                if counts.cash > 0 {
                    SkeletonSection(title: Terms.cash, count: counts.cash) { skeletonCard.clearListRow() }
                }
                if counts.bank > 0 {
                    SkeletonSection(title: Terms.bankAccount, count: counts.bank) { skeletonCard.clearListRow() }
                }
                if counts.creditCard > 0 {
                    SkeletonSection(title: "信用卡", count: counts.creditCard) { skeletonCard.clearListRow() }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入帳戶", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                GlassCapsuleButton(title: "重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            List {
                summarySection
                cashSection
                bankSection
                creditCardSection
            }
            .refreshable { await model.load() }
        }
    }

    private var skeletonCard: some View {
        NumberCard(title: "帳戶名稱", symbol: "building.columns", symbolColor: .gray, amount: .plain(Skeleton.amount), caption: "佔位", spokenText: "")
            .skeletonCell("accounts.skeleton.card")
            .skeletonRow()
    }

    /// 主視覺(#119):超大的淨可用餘額與組成比例條，下面是三格數字磚。
    /// 帳戶數不寫(section 標題有);已出帳待繳款、未出帳款在信用卡詳細頁。
    @ViewBuilder
    private var summarySection: some View {
        if model.showsPendingAdvanceBanner {
            Section {
                PendingAdvancesBanner(text: model.pendingAdvanceBannerText) { showTab(.household) }
                    .clearListRow()
            }
        }
        Section {
            AccountsHero(
                balance: model.availableBalance ?? .zero, segments: model.composition, summary: model.compositionSummary
            )
            .clearListRow()
        }
        Section {
            NumberTileRow(memory: model.skeletonShape) {
                NumberTile(title: Terms.cash, amount: .plain(model.cashTotal ?? .zero), spokenTitle: "\(Terms.cash)總額")
                NumberTile(title: Terms.bankAccount, amount: .plain(model.bankBalanceTotal ?? .zero), spokenTitle: "\(Terms.bankAccount)餘額合計")
                NumberTile(title: "信用卡待繳", amount: .outflow(model.totalCardDue ?? .zero), spokenTitle: "信用卡待繳總額")
            }
            .clearListRow()
        }
        .compactSectionSpacing()
    }

    private var cashSection: some View {
        Section("\(Terms.cash)(\(model.cashWallets.count))") {
            if model.cashWallets.isEmpty {
                SectionEmptyState(
                    title: "目前此範圍無\(Terms.cash)",
                    actionTitle: "立即建立\(Terms.cash)", identifier: "accounts.emptyAdd.cash"
                ) { editor = EditorSheet(model.makeEditor(adding: .cash)) }
            }
            ForEach(model.cashWallets) { wallet in
                accountRow(.cash(wallet)) {
                    fundCard(
                        name: wallet.name, symbol: "wallet.bifold", colorHex: wallet.colorHex, isJointFund: wallet.isJointFund,
                        balance: wallet.balance, balanceTitle: "\(Terms.cash)餘額"
                    )
                }
            }
        }
    }

    private var bankSection: some View {
        Section("\(Terms.bankAccount)(\(model.bankAccounts.count))") {
            if model.bankAccounts.isEmpty {
                SectionEmptyState(
                    title: "目前此範圍無\(Terms.bankAccount)",
                    actionTitle: "立即新增\(Terms.bankAccount)", identifier: "accounts.emptyAdd.bank"
                ) { editor = EditorSheet(model.makeEditor(adding: .bank)) }
            }
            ForEach(model.bankAccounts) { account in
                accountRow(.bank(account)) {
                    fundCard(
                        name: account.name, symbol: "building.columns", colorHex: account.colorHex, isJointFund: account.isJointFund,
                        balance: account.balance, balanceTitle: "餘額", warnsWhenNegative: true,
                        debit: model.debitPreview(for: account)
                    )
                }
            }
        }
    }

    private var creditCardSection: some View {
        Section("信用卡(\(model.creditCards.count))") {
            if model.creditCards.isEmpty {
                SectionEmptyState(
                    title: "目前此範圍無信用卡",
                    actionTitle: "立即新增信用卡", identifier: "accounts.emptyAdd.creditCard"
                ) { editor = EditorSheet(model.makeEditor(adding: .creditCard)) }
            }
            ForEach(model.creditCards) { card in
                creditCardRow(card)
            }
        }
    }

    /// 現金錢包、銀行存款帳戶的卡片(#119、#138):名稱加大金額，下面一行小字是歸屬(家庭公帳或個人私帳)。
    /// VoiceOver 念名稱、餘額、歸屬。
    private func fundCard(
        name: String, symbol: String, colorHex: String, isJointFund: Bool, balance: Money, balanceTitle: String,
        warnsWhenNegative: Bool = false, debit: BankDebitPreview? = nil
    ) -> some View {
        NumberCard(
            title: name, symbol: symbol, symbolColor: Color(hex: colorHex) ?? .gray,
            amount: warnsWhenNegative ? .stock(balance) : .plain(balance), caption: OwnershipName.title(isShared: isJointFund),
            spokenText: "\(name),\(balanceTitle) \(balance.spokenText),\(OwnershipName.title(isShared: isJointFund))"
                + (debit.map { ",\($0.spokenText)" } ?? ""),
            notes: debit?.notes ?? [], reservesMenuSpace: true
        )
    }

    /// 信用卡卡片(#119、#73):名稱、待繳金額(有待繳時紅色)、歸屬與繳款日;整張卡點進信用卡詳細頁，⋯ 與往左滑同其他帳戶。
    /// 沒有對應欠款的繳款項目、沒有未出帳款時的出帳作業都隱藏。
    private func creditCardRow(_ card: CreditCard) -> some View {
        accountRow(.creditCard(card), identifier: "accounts.card.\(card.id.rawValue)") {
            NumberCard(
                title: card.name, symbol: "creditcard", symbolColor: Color(hex: card.colorHex) ?? .gray, amount: .outflow(card.totalDue),
                caption: model.caption(for: card), spokenText: model.spokenSummary(of: card), reservesMenuSpace: true
            )
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension CardPaymentModel: Identifiable {}
extension TransferModel: Identifiable {}

/// 區塊沒有帳戶時的空狀態(web 的「目前此範圍無…」):只有標題和新增的入口，web 的宣傳句不寫(DESIGN.md「說明文字」)。
private struct SectionEmptyState: View {
    let title: String
    let actionTitle: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            // 玻璃膠囊(#134);大字級折行時文字置中。
            GlassCapsuleButton(title: actionTitle, action: action)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// 公帳範圍的「家庭公帳待報銷代墊款」橫幅(上游 ADR 0015、#141):金額單行，附玻璃膠囊「前往家庭」報銷。
/// VoiceOver 念一句完整的話，按鈕另外一個元素。
private struct PendingAdvancesBanner: View {
    let text: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "doc.text")
                .font(.headline)
                .monospacedDigit()
                // 照系統字級、不縮小(#156):放不下就折行。
                .accessibilityIdentifier("accounts.pendingAdvances")
            GlassCapsuleButton(title: "前往家庭", systemImage: "arrow.right", action: action)
                .accessibilityIdentifier("accounts.pendingAdvances.open")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
