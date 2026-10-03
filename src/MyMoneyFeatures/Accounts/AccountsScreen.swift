import Foundation
import MyMoneyDomain
import SwiftUI

/// 「帳戶」tab:數字優先的主視覺(淨可用餘額、組成比例條、三格數字磚、ATM 提款／轉帳膠囊按鈕)，
/// 現金錢包、銀行存款帳戶與信用卡帳戶三區的卡片(parity.md「帳戶」,#119)。
/// toolbar 有帳戶檢視範圍的篩選按鈕(目前的選擇由按鈕的圖示狀態表達)、新增資產帳戶和頭像三顆。
/// 每個帳戶是一張卡片(整列);信用卡點進信用卡詳細頁(#73)。
struct AccountsScreen: View {
    @Bindable var model: AccountsModel
    /// 切到別的 tab(待報銷橫幅的「前往家庭」)。
    var showTab: (AppTab) -> Void = { _ in }
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: Account?
    @State private var pendingRollover: CreditCard?
    @State private var payment: CardPaymentModel?
    @State private var transfer: TransferModel?
    /// 點信用卡卡片 push 信用卡詳細頁。卡片不是 `NavigationLink`:列表裡的連結會多一個箭頭。
    @State private var cardPath: [CreditCard] = []

    var body: some View {
        NavigationStack(path: $cardPath) {
            content
                .skeletonTransition(value: model.phase)
                .tabRootNavigation("帳戶")
                .toolbar {
                    ScopeFilter("帳戶檢視範圍", scope: $model.scope, identifier: "accounts.scope")
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("新增現金錢包", systemImage: "wallet.bifold") {
                                editor = EditorSheet(model.makeEditor(adding: .cash))
                            }
                            Button("新增銀行存款帳戶", systemImage: "building.columns") {
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
                .task(id: QueryKey(scope: model.scope, version: model.dataVersion.value)) {
                    await model.refreshIfStale()
                }
                // 詳細頁的 model 由這裡(路由)建立，跟帳戶頁同一個帳戶檢視範圍。
                .navigationDestination(for: CreditCard.self) { card in
                    CreditCardDetailScreen(model: model.makeCardDetail(for: card))
                }
                .sheet(item: $editor) { sheet in
                    AccountEditorView(model: sheet.model)
                }
                .confirmationDialog(
                    "刪除資產帳戶",
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    titleVisibility: .visible,
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
                .confirmationDialog(
                    "結帳日出帳作業",
                    isPresented: Binding(get: { pendingRollover != nil }, set: { if !$0 { pendingRollover = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingRollover
                ) { card in
                    Button("出帳作業") {
                        Task { await model.rollOver(card) }
                    }
                    Button("取消", role: .cancel) {}
                } message: { card in
                    Text(model.rolloverConfirmation(for: card))
                }
                .alert(
                    "無法完成",
                    isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
                ) {
                    Button("好") {}
                } message: {
                    Text(model.alertMessage ?? "")
                }
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

    private struct QueryKey: Equatable {
        let scope: AccountScope
        let version: Int
    }

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: AccountEditorModel

        init(_ model: AccountEditorModel) {
            self.model = model
        }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認：後端刪除無法復原)。
    /// `transferTitle` 有值時，往右滑和長按多一個轉帳動作(現金錢包是「ATM 提款」,銀行存款帳戶是「轉帳／提款」)。
    /// 沒有編輯權限的帳戶(別人建立的家庭共同帳戶，上游 ADR 0013、#133)點不開、沒有編輯與刪除，轉帳照舊。
    @ViewBuilder
    private func accountRow(
        _ account: Account,
        transferTitle: String? = nil,
        openTransfer: @escaping () -> TransferModel? = { nil },
        @ViewBuilder label: () -> some View
    ) -> some View {
        let canModify = model.canModify(account)
        Group {
            if canModify {
                Button {
                    editor = EditorSheet(model.makeEditor(editing: account))
                } label: {
                    label()
                }
                .buttonStyle(.plain)
            } else {
                label()
            }
        }
        .clearListRow()
        .swipeActions {
            if canModify {
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = account
                }
            }
        }
        .swipeActions(edge: .leading) {
            if let transferTitle {
                // 滑動動作的字固定是白色，深色模式 accent 是白色會白底白字:用中性灰(#134)。
                Button(transferTitle, systemImage: "arrow.left.arrow.right") { transfer = openTransfer() }
                    .tint(.gray)
            }
        }
        .contextMenu {
            if canModify {
                Button("編輯", systemImage: "pencil") {
                    editor = EditorSheet(model.makeEditor(editing: account))
                }
            }
            if let transferTitle {
                Button(transferTitle, systemImage: "arrow.left.arrow.right") { transfer = openTransfer() }
            }
            if canModify {
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = account
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        BigNumber(title: "淨可用餘額", amount: Skeleton.amount)
                        SkeletonChart(height: 12)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .skeletonAnnouncement()
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
                SkeletonSection(title: "現金錢包", count: 1) { skeletonCard.clearListRow() }
                SkeletonSection(title: "銀行存款帳戶", count: 2) { skeletonCard.clearListRow() }
                SkeletonSection(title: "信用卡", count: 1) { skeletonCard.clearListRow() }
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
        NumberCard(title: "帳戶名稱", symbol: "building.columns", symbolColor: .gray, amount: Skeleton.amount, caption: "佔位", spokenText: "")
            .skeletonRow()
    }

    /// 主視覺(#119):超大的淨可用餘額與組成比例條，下面是三格數字磚和 ATM 提款／轉帳的膠囊按鈕。
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
            NumberTileRow {
                NumberTile(title: "現金", amount: model.cashTotal ?? .zero, spokenTitle: "現金錢包總額")
                NumberTile(title: "銀行存款", amount: model.bankBalanceTotal ?? .zero, spokenTitle: "銀行存款帳戶餘額合計")
                NumberTile(
                    title: "信用卡待繳", amount: model.totalCardDue ?? .zero,
                    style: (model.totalCardDue ?? .zero) > .zero ? .red : nil, spokenTitle: "信用卡待繳總額"
                )
            }
            .clearListRow()
            // ATM 提款／轉帳:醒目的膠囊按鈕，在摘要下面(ADR-0004、#87、#119);現金錢包卡、銀行存款帳戶卡的滑動捷徑照舊。
            TransferCapsuleButton {
                transfer = model.makeTransfer()
            }
            .clearListRow()
        }
        .compactSectionSpacing()
    }

    private var cashSection: some View {
        Section("現金錢包(\(model.cashWallets.count))") {
            if model.cashWallets.isEmpty {
                SectionEmptyState(
                    title: "目前此範圍無現金錢包",
                    actionTitle: "立即建立現金錢包", identifier: "accounts.emptyAdd.cash"
                ) { editor = EditorSheet(model.makeEditor(adding: .cash)) }
            }
            ForEach(model.cashWallets) { wallet in
                accountRow(.cash(wallet), transferTitle: "ATM 提款", openTransfer: { model.makeTransfer(to: wallet.id) }) {
                    fundCard(
                        name: wallet.name, symbol: "wallet.bifold", colorHex: wallet.colorHex, isJointFund: wallet.isJointFund,
                        balance: wallet.balance, balanceTitle: "現金錢包餘額"
                    )
                }
            }
        }
    }

    private var bankSection: some View {
        Section("銀行存款帳戶(\(model.bankAccounts.count))") {
            if model.bankAccounts.isEmpty {
                SectionEmptyState(
                    title: "目前此範圍無銀行存款帳戶",
                    actionTitle: "立即新增銀行存款帳戶", identifier: "accounts.emptyAdd.bank"
                ) { editor = EditorSheet(model.makeEditor(adding: .bank)) }
            }
            ForEach(model.bankAccounts) { account in
                accountRow(.bank(account), transferTitle: "轉帳／提款", openTransfer: { model.makeTransfer(from: account.id) }) {
                    fundCard(
                        name: account.name, symbol: "building.columns", colorHex: account.colorHex, isJointFund: account.isJointFund,
                        balance: account.balance, balanceTitle: "餘額", warnsWhenNegative: true
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
        warnsWhenNegative: Bool = false
    ) -> some View {
        NumberCard(
            title: name, symbol: symbol, symbolColor: Color(hex: colorHex) ?? .gray, amount: balance,
            isWarning: warnsWhenNegative && balance < .zero, caption: OwnershipName.title(isShared: isJointFund),
            spokenText: "\(name),\(balanceTitle) \(balance.spokenText),\(OwnershipName.title(isShared: isJointFund))"
        )
    }

    /// 信用卡卡片(#119、#73):名稱、待繳金額(有待繳時紅色)、歸屬與繳款日;整張卡點進信用卡詳細頁。
    /// 往左滑可以刪除;長按有繳款、出帳作業、編輯和刪除的捷徑，每一項在詳細頁都找得到(HIG Context menus)。
    /// 沒有對應欠款的繳款項目、沒有未出帳款時的出帳作業都隱藏。
    private func creditCardRow(_ card: CreditCard) -> some View {
        Button {
            cardPath.append(card)
        } label: {
            NumberCard(
                title: card.name, symbol: "creditcard", symbolColor: Color(hex: card.colorHex) ?? .gray, amount: card.totalDue,
                isWarning: card.isDue, caption: model.caption(for: card), spokenText: model.spokenSummary(of: card)
            )
        }
        .buttonStyle(.plain)
        .clearListRow()
        .accessibilityIdentifier("accounts.card.\(card.id.rawValue)")
        .swipeActions {
            if model.canModify(.creditCard(card)) {
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = .creditCard(card)
                }
            }
        }
        .contextMenu {
            // 還款、出帳作業只有能操作這張卡的人;編輯、刪除只有能修改這個帳戶的人(上游 ADR 0013、#133)。
            let presets = model.paymentPresets(for: card)
            if !presets.isEmpty || model.showsRollover(card) {
                Section {
                    ForEach(presets, id: \.self) { preset in
                        Button(preset.title, systemImage: preset.systemImage) {
                            payment = model.makePayment(for: card, preset: preset)
                        }
                    }
                    if model.showsRollover(card) {
                        Button("出帳作業", systemImage: "calendar.badge.clock") { pendingRollover = card }
                    }
                }
            }
            if model.canModify(.creditCard(card)) {
                Button("編輯", systemImage: "pencil") {
                    editor = EditorSheet(model.makeEditor(editing: .creditCard(card)))
                }
                Button("刪除", systemImage: "trash", role: .destructive) {
                    pendingDeletion = .creditCard(card)
                }
            }
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
