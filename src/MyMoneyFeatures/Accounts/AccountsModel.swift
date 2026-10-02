import Foundation
import MyMoneyDomain
import Observation

/// 帳戶頁(瀏覽)的 model(parity.md「帳戶」)。
@MainActor
@Observable
public final class AccountsModel {
    public enum Phase: Equatable {
        /// 第一次載入，還沒有任何資料:畫面只顯示載入中，不顯示 `$0`。
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading

    /// 帳戶檢視範圍(web 的「檢視範圍」):全部(本人 + 家庭公用)、家庭公用、個人私帳。
    /// 畫面在範圍改變時重新載入(`.task(id:)`)。
    public var scope: AccountScope = .all

    public private(set) var cashWallets: [CashWallet] = []
    public private(set) var bankAccounts: [BankAccount] = []
    public private(set) var creditCards: [CreditCard] = []
    private var summary: BalanceSummary?

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    /// 操作成功時顯示的訊息(例如結帳日出帳作業的結果)。
    public var noticeMessage: String?

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    /// 編輯與刪除的權限(上游 ADR 0013、#133);沒有就不擋，交給後端。
    @ObservationIgnored private let permissions: PermissionsModel?

    public init(
        repository: any AccountRepository,
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        self.permissions = permissions
        self.today = today
    }

    /// 編輯與刪除:個人私帳只有本人;家庭共同帳戶是建立者或家庭管理員(上游 ADR 0013、#133)。
    public func canModify(_ account: Account) -> Bool {
        permissions?.current.canModify(account) ?? true
    }

    /// 信用卡的還款沖銷、出帳作業、校準:個人信用卡只有持卡人;家庭信用卡全員都可以。
    public func canOperate(_ card: CreditCard) -> Bool {
        permissions?.current.canOperate(card) ?? true
    }

    /// 有未出帳款就能做結帳日出帳作業(長按選單)。
    public func showsRollover(_ card: CreditCard) -> Bool {
        card.canRollOver
    }

    /// 例如「確定要將「卡名」的未出帳款 $3,500 轉入本期已出帳待繳款嗎？」,跟詳細頁的一樣。
    public func rolloverConfirmation(for card: CreditCard) -> String {
        card.rolloverConfirmation
    }

    /// 結帳日出帳作業;成功後顯示後端的訊息，並遞增資料版本。
    public func rollOver(_ card: CreditCard) async {
        guard canOperate(card) else { return }
        do {
            noticeMessage = try await repository.rollOverStatement(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 信用卡扣款還款的 sheet(從信用卡精簡列的長按選單打開):扣款帳戶只列出銀行存款帳戶。
    public func makePayment(for card: CreditCard, preset: CardPaymentModel.Preset) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion, today: today
        )
    }

    /// 上一次載入時的資料版本與檢視範圍;跟目前的不同時就要重抓。
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: AccountScope?

    public func deleteConfirmation(for account: Account) -> String {
        "確定要刪除帳戶「\(account.name)」嗎？這個帳戶的交易記錄也會一併刪除！"
    }

    /// 刪除資產帳戶;成功後遞增資料版本(帳戶頁與其他畫面都會重抓)。
    public func delete(_ account: Account) async {
        guard canModify(account) else { return }
        do {
            try await repository.delete(account.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 資料版本或檢視範圍在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value || loadedScope != scope else { return }
        await load()
    }

    /// ATM 提款／帳戶互轉的 sheet。從某個帳戶的按鈕打開時，預先選好轉出或轉入。
    public func makeTransfer(from: AccountID? = nil, to: AccountID? = nil) -> TransferModel {
        TransferModel(repository: repository, dataVersion: dataVersion, today: today, preferredFrom: from, preferredTo: to)
    }

    /// 信用卡詳細頁(點信用卡精簡列 push):跟帳戶頁同一個帳戶檢視範圍，扣款帳戶是這個範圍的銀行存款帳戶。
    public func makeCardDetail(for card: CreditCard) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: bankAccounts, loadedVersion: loadedVersion, scope: scope, repository: repository,
            dataVersion: dataVersion, permissions: permissions, today: today
        )
    }

    public func makeEditor(adding kind: AccountKind) -> AccountEditorModel {
        AccountEditorModel(adding: kind, repository: repository, dataVersion: dataVersion)
    }

    public func makeEditor(editing account: Account) -> AccountEditorModel {
        AccountEditorModel(editing: account, repository: repository, dataVersion: dataVersion)
    }

    /// 現金錢包的餘額合計;還沒載入時是 `nil`。
    public var cashTotal: Money? { summary?.cashTotal }

    /// 銀行存款帳戶的餘額合計;還沒載入時是 `nil`。
    public var bankBalanceTotal: Money? { summary?.bankBalanceTotal }

    /// 所有信用卡帳戶的信用卡待繳總額(已出帳待繳款加未出帳款)。兩者各自的金額在信用卡詳細頁(#75)。
    public var totalCardDue: Money? { summary.map { $0.billedDebtTotal + $0.unbilledDebtTotal } }

    /// 淨可用餘額(後端依帳戶檢視範圍計算)。
    public var availableBalance: Money? { summary?.availableBalance }

    /// 組成比例條(#119):現金、銀行存款、信用卡待繳各佔多少，用後端的資金指標算出顯示比例。
    /// 只列金額大於 0 的項目(透支的銀行存款不畫);全部是 0 或還沒載入時是空的。
    public var composition: [CompositionSegment] {
        guard let summary else { return [] }
        let parts: [(CompositionSegment.Kind, Money)] = [
            (.cash, summary.cashTotal), (.bank, summary.bankBalanceTotal),
            (.cardDue, summary.billedDebtTotal + summary.unbilledDebtTotal),
        ].filter { $0.1 > .zero }
        let total = parts.reduce(Money.zero) { $0 + $1.1 }
        return parts.map { kind, amount in
            CompositionSegment(kind: kind, amount: amount, fraction: NSDecimalNumber(decimal: amount.amount / total.amount).doubleValue)
        }
    }

    /// 比例條的 VoiceOver 摘要，例如「資金組成，現金百分之 2，銀行存款百分之 63，信用卡待繳百分之 36」;沒有比例條時是 `nil`。
    public var compositionSummary: String? {
        let segments = composition
        guard !segments.isEmpty else { return nil }
        let parts = segments.map { "\($0.kind.title)百分之 \(Int(($0.fraction * 100).rounded(.toNearestOrAwayFromZero)))" }
        return (["資金組成"] + parts).joined(separator: "，")
    }

    /// 載入這個範圍的資產帳戶與資金指標。重新載入(下拉更新)時保留舊資料，不回到載入中。
    public func load() async {
        let version = dataVersion.value
        let scope = scope
        do {
            async let accounts = repository.accounts(scope: scope)
            async let summary = repository.balanceSummary(scope: scope)
            let (loadedAccounts, loadedSummary) = try await (accounts, summary)
            // 被取消(換了範圍)或已經過期的結果不套用。
            guard !Task.isCancelled, scope == self.scope else { return }
            cashWallets = loadedAccounts.compactMap { if case .cash(let wallet) = $0 { wallet } else { nil } }
            bankAccounts = loadedAccounts.compactMap { if case .bank(let account) = $0 { account } else { nil } }
            creditCards = loadedAccounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            self.summary = loadedSummary
            loadedVersion = version
            loadedScope = scope
            phase = .loaded
            await permissions?.loadIfNeeded()
        } catch {
            // 被取消的載入(換了範圍)不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

extension AccountKind {
    /// 資產帳戶類型的名稱(CONTEXT.md)。
    public var title: String {
        switch self {
        case .cash: "現金錢包"
        case .bank: "銀行存款帳戶"
        case .creditCard: "信用卡"
        }
    }
}

extension Account {
    /// 帳戶選單項目的副標題：類型，例如「現金錢包」。選擇列的值只放名稱，餘額另起一列「可用餘額」
    /// (DESIGN.md「列與欄位」第 7 條，#78)。類型照實標示(web 的週期收支把現金錢包標成「信用卡」,不照抄)。
    public var menuSubtitle: String { kind.title }

    /// 現金錢包和銀行存款帳戶的餘額;信用卡沒有「餘額」,是 `nil`。
    public var fundsBalance: Money? {
        switch self {
        case .cash(let wallet): wallet.balance
        case .bank(let bank): bank.balance
        case .creditCard: nil
        }
    }
}

extension ReceivingAccount {
    /// 撥款報銷收款帳戶選單項目的副標題：類型。不含餘額(其他成員個人私帳的餘額不公開)。
    public var menuSubtitle: String { kind.title }
}

/// 帳戶頁組成比例條的一段(#119)。
public struct CompositionSegment: Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case cash
        case bank
        case cardDue

        /// 圖例與 VoiceOver 的名稱。
        public var title: String {
            switch self {
            case .cash: "現金"
            case .bank: "銀行存款"
            case .cardDue: "信用卡待繳"
            }
        }
    }

    public let kind: Kind
    public let amount: Money
    /// 佔三項合計的比例(0 到 1)。
    public let fraction: Double

    public var id: Kind { kind }
}
