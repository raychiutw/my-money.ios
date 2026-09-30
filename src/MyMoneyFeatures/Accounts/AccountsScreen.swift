import Foundation
import MyMoneyDomain
import SwiftUI

/// 「帳戶」tab:摘要(淨可用餘額和它的組成),現金錢包、銀行存款帳戶與信用卡帳戶三區(parity.md「帳戶」)。
/// toolbar 有帳戶檢視範圍的篩選按鈕(目前的選擇顯示在導覽列副標題)、ATM 提款／轉帳和新增資產帳戶。
/// 信用卡是精簡列，點進信用卡詳細頁(#73)。
struct AccountsScreen: View {
    @Bindable var model: AccountsModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: Account?
    @State private var pendingRollover: CreditCard?
    @State private var payment: CardPaymentModel?
    @State private var transfer: TransferModel?

    var body: some View {
        NavigationStack {
            content
                .skeletonTransition(value: model.phase)
                .navigationTitle("帳戶")
                .navigationSubtitle(model.scope.title)
                .toolbar {
                    ScopeFilter("帳戶檢視範圍", scope: $model.scope, identifier: "accounts.scope")
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            transfer = model.makeTransfer()
                        } label: {
                            Label("ATM 提款／轉帳", systemImage: "arrow.left.arrow.right")
                        }
                        .accessibilityIdentifier("accounts.transfer")
                    }
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
    private func accountRow(
        _ account: Account,
        transferTitle: String? = nil,
        openTransfer: @escaping () -> TransferModel? = { nil },
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            editor = EditorSheet(model.makeEditor(editing: account))
        } label: {
            label()
        }
        .tint(.primary)
        .swipeActions {
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = account
            }
        }
        .swipeActions(edge: .leading) {
            if let transferTitle {
                Button(transferTitle, systemImage: "arrow.left.arrow.right") { transfer = openTransfer() }
                    .tint(.accentColor)
            }
        }
        .contextMenu {
            Button("編輯", systemImage: "pencil") {
                editor = EditorSheet(model.makeEditor(editing: account))
            }
            if let transferTitle {
                Button(transferTitle, systemImage: "arrow.left.arrow.right") { transfer = openTransfer() }
            }
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = account
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                Section {
                    SummaryRow(title: "淨可用餘額", amount: Skeleton.amount)
                        .skeletonAnnouncement()
                    ForEach(0..<3, id: \.self) { _ in
                        AmountRow(title: "摘要數字", amount: Skeleton.amount)
                            .skeletonRow()
                    }
                }
                SkeletonSection(title: "現金錢包", count: 1) { SkeletonAccountRow() }
                SkeletonSection(title: "銀行存款帳戶", count: 2) { SkeletonAccountRow() }
                SkeletonSection(title: "信用卡", count: 1) { SkeletonAccountRow() }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入帳戶", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重試") {
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

    /// 摘要(#75):淨可用餘額是主數字，下面是它的組成，一項一列。
    /// 帳戶數不寫(section 標題有);已出帳待繳款、未出帳款在信用卡詳細頁。
    private var summarySection: some View {
        Section {
            SummaryRow(title: "淨可用餘額", amount: model.availableBalance ?? .zero, warnsWhenNegative: true)
            AmountRow(title: "現金錢包總額", amount: model.cashTotal ?? .zero)
            AmountRow(title: "銀行存款帳戶餘額合計", amount: model.bankBalanceTotal ?? .zero)
            AmountRow(title: "信用卡待繳總額", amount: model.totalCardDue ?? .zero)
        }
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
                    FundAccountRow(
                        name: wallet.name, colorHex: wallet.colorHex, isJointFund: wallet.isJointFund,
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
                    FundAccountRow(
                        name: account.name, colorHex: account.colorHex, isJointFund: account.isJointFund,
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

    /// 信用卡精簡列(#73):整列是導覽連結，點進信用卡詳細頁。往左滑可以刪除;長按有繳款、出帳作業、編輯和刪除的捷徑，
    /// 每一項在詳細頁都找得到(HIG Context menus)。沒有對應欠款的繳款項目、沒有未出帳款時的出帳作業都隱藏。
    private func creditCardRow(_ card: CreditCard) -> some View {
        NavigationLink(value: card) {
            CreditCardSummaryRow(card: card, mark: .colorBar)
        }
        .accessibilityIdentifier("accounts.card.\(card.id.rawValue)")
        .swipeActions {
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = .creditCard(card)
            }
        }
        .contextMenu {
            Section {
                ForEach(card.paymentPresets, id: \.self) { preset in
                    Button(preset.title, systemImage: preset.systemImage) {
                        payment = model.makePayment(for: card, preset: preset)
                    }
                }
                if model.showsRollover(card) {
                    Button("出帳作業", systemImage: "calendar.badge.clock") { pendingRollover = card }
                }
            }
            Button("編輯", systemImage: "pencil") {
                editor = EditorSheet(model.makeEditor(editing: .creditCard(card)))
            }
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = .creditCard(card)
            }
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension CardPaymentModel: Identifiable {}
extension TransferModel: Identifiable {}

/// 現金錢包、銀行存款帳戶的列：色條、名稱(家庭共同基金多一行標記)和餘額。
/// 用 `LabeledContent`:放不下同一行時(AX5)自動上下堆疊，金額一律單行(DESIGN.md「列與欄位」第 5 條，#79)。
private struct FundAccountRow: View {
    let name: String
    let colorHex: String
    let isJointFund: Bool
    let balance: Money
    /// VoiceOver 在餘額前念的標籤，例如「現金錢包餘額」。
    let balanceTitle: String
    /// 負數用紅色(銀行存款帳戶)。
    var warnsWhenNegative = false

    var body: some View {
        LabeledContent {
            Text(balance.formatted())
                .monospacedDigit()
                .foregroundStyle(warnsWhenNegative && balance < .zero ? Color.red : .primary)
                .lineLimit(1)
                .fixedSize()
        } label: {
            HStack(spacing: 12) {
                AccountColorMark(hex: colorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if isJointFund {
                        Label("家庭共同基金", systemImage: "house.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)\(isJointFund ? ",家庭共同基金" : ""),\(balanceTitle) \(balance.spokenText)")
    }
}

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
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .accessibilityIdentifier(identifier)
        }
    }
}
