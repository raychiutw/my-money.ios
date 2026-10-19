import Foundation
import MyMoneyDomain
import Observation

/// 現金與活存帳戶詳細頁的 model:跟信用卡詳細頁同一個作法(從帳戶頁 push、由路由建立、資料版本改變就重新取得)。
/// 資訊只用現有欄位:餘額、歸屬、活存帳戶的待扣卡費預覽;動作都在 ⋯ 選單(轉帳、編輯、刪除)。
@MainActor
@Observable
public final class AccountDetailModel: Alerting {
    /// 目前的帳戶(現金或活存)。
    public private(set) var account: Account
    /// 活存帳戶的待扣卡費預覽;沒有卡綁定它、或是現金時是 `nil`。
    public private(set) var debitPreview: BankDebitPreview?
    public private(set) var bankAccounts: [BankAccount]

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?
    /// 轉帳成功時顯示的訊息(後端回傳的原文)。
    public var noticeMessage: String?
    /// 重新取得時，這個帳戶已經不在這個帳戶檢視範圍(被刪除，或歸屬改了):畫面回到上一頁。
    public private(set) var isGone = false

    @ObservationIgnored private let scope: AccountScope
    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let context: SessionContext
    @ObservationIgnored private let permissions: PermissionsModel?
    @ObservationIgnored private var freshness = LoadFreshness<Unscoped>()

    public var dataVersion: DataVersion { context.dataVersion }
    private var today: () -> CalendarDay { context.today }
    public var reloadKey: ReloadKey<Unscoped> { ReloadKey(version: dataVersion.value) }

    init(
        account: Account,
        debitPreview: BankDebitPreview?,
        bankAccounts: [BankAccount],
        loadedVersion: Int?,
        scope: AccountScope,
        repository: any AccountRepository,
        permissions: PermissionsModel?,
        context: SessionContext
    ) {
        self.account = account
        self.debitPreview = debitPreview
        self.bankAccounts = bankAccounts
        self.scope = scope
        self.repository = repository
        self.permissions = permissions
        self.context = context
        if let loadedVersion { freshness.markLoaded(ReloadKey(version: loadedVersion)) }
    }

    public var canModify: Bool { permissions?.current.canModify(account) ?? true }

    /// 資訊列:餘額(現金叫「現金餘額」)與歸屬。
    public var rows: [CardDetailRow] {
        let balance = account.fundsBalance ?? .zero
        let title: String = if case .cash = account { "\(Terms.cash)餘額" } else { "餘額" }
        return [
            CardDetailRow(title, balance.formatted()),
            CardDetailRow("歸屬", OwnershipName.title(isShared: account.isJointFund)),
        ]
    }

    /// ⋯ 選單的項目,跟帳戶頁的列一樣。
    public var menuItems: [AccountMenuItem] {
        AccountMenuItem.items(for: account, canModify: canModify, canOperate: false, paymentPresets: [], showsRollover: false)
    }

    /// 轉帳的 sheet:這個帳戶是轉入，轉出留給使用者選(上游 ADR 0011)。
    public func makeTransfer() -> TransferModel {
        TransferModel(repository: repository, dataVersion: dataVersion, today: today, preferredTo: account.id)
    }

    public func makeEditor() -> AccountEditorModel {
        AccountEditorModel(editing: account, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion)
    }

    public var deleteConfirmation: String {
        "確定要刪除帳戶「\(account.name)」嗎？這個帳戶的\(Terms.transactions)也會一併刪除！"
    }

    /// 刪除;成功後遞增資料版本(帳戶頁與其他畫面重抓，這一頁取得時發現帳戶不見而回到上一頁)。
    public func delete() async {
        guard canModify else { return }
        _ = await commit(dataVersion) { try await repository.delete(account.id) }
    }

    /// 資料版本在上一次取得之後改變過，才重新取得。
    public func refreshIfStale() async {
        guard freshness.isStale(reloadKey) else { return }
        await load()
    }

    public func load() async {
        let key = reloadKey
        do {
            let accounts = try await repository.accounts(scope: scope)
            guard !Task.isCancelled else { return }
            guard let fresh = accounts.first(where: { $0.id == account.id }) else {
                isGone = true
                return
            }
            account = fresh
            bankAccounts = accounts.compactMap { if case .bank(let bank) = $0 { bank } else { nil } }
            if case .bank(let bank) = fresh {
                let cards = accounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
                debitPreview = BankDebitPreview.make(for: bank, cards: cards.filter { !(permissions?.current.isMasked($0) ?? $0.isMasked) })
            }
            freshness.markLoaded(key)
        } catch {
            guard !Task.isCancelled else { return }
            alertMessage = error.localizedDescription
        }
    }
}
