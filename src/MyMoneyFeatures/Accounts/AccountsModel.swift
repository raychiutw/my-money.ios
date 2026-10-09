import Foundation
import MyMoneyDomain
import Observation

/// 帳戶頁(瀏覽)的 model(parity.md「帳戶」)。
@MainActor
@Observable
public final class AccountsModel: Alerting {
    public typealias Phase = LoadPhase

    public private(set) var phase: Phase = .loading

    /// 帳戶檢視範圍(web 的「檢視範圍」):全部、家庭公帳、個人私帳。
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
    /// 公帳範圍的待報銷橫幅用(上游 ADR 0015、#141);沒有就不顯示橫幅。
    @ObservationIgnored private let households: (any HouseholdRepository)?
    @ObservationIgnored private let defaults: UserDefaults

    /// 骨架屏各區塊的張數(#204):上次載入完成時的張數(依範圍),第一次沒有記錄時現金 0、活存帳戶 1、信用卡 1。
    public struct SkeletonCounts: Equatable, Sendable {
        public let cash: Int
        public let bank: Int
        public let creditCard: Int

        public init(cash: Int, bank: Int, creditCard: Int) {
            self.cash = cash
            self.bank = bank
            self.creditCard = creditCard
        }
    }

    private var skeletonMemory: SkeletonShapeMemory { SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.accounts") }

    public var skeletonCounts: SkeletonCounts {
        let memory = skeletonMemory
        return SkeletonCounts(
            cash: memory.count(for: "cash.\(scope)", default: 0), bank: memory.count(for: "bank.\(scope)", default: 1),
            creditCard: memory.count(for: "card.\(scope)", default: 1)
        )
    }

    /// 骨架屏的形狀記憶(#204、#208):數字磚(`tiles`)的排法與各區塊張數(依範圍)。
    public var skeletonShape: SkeletonShapeMemory { skeletonMemory }

    /// 公帳範圍:各成員待報銷的代墊款加總(web 也是這樣加，不是 iOS 重算業務規則);其他範圍、取不到、沒有家庭時是 `nil`。
    public private(set) var pendingAdvanceTotal: Money?

    public init(
        repository: any AccountRepository,
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        households: (any HouseholdRepository)? = nil,
        defaults: UserDefaults = .standard,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.defaults = defaults
        self.repository = repository
        self.dataVersion = dataVersion
        self.permissions = permissions
        self.households = households
        self.today = today
    }

    /// 畫面上是公帳範圍的內容、而且有成員待報銷代墊款(大於 0)才顯示橫幅。
    public var showsPendingAdvanceBanner: Bool {
        freshness.scope == .household && (pendingAdvanceTotal ?? .zero) > .zero
    }

    /// 橫幅的一句話，例如「家庭公帳待報銷總額 $850」。
    public var pendingAdvanceBannerText: String {
        "家庭公帳\(Terms.pendingReimbursementTotal) \((pendingAdvanceTotal ?? .zero).formatted())"
    }

    /// 公帳範圍:各成員待報銷的加總;只在公帳範圍多問一次，取不到(或沒有家庭)是 `nil`，不影響帳戶頁其他區塊。
    private func fetchPendingAdvanceTotal(for scope: AccountScope) async -> Money? {
        guard scope == .household, let households else { return nil }
        guard let advances = try? await households.advances() else { return nil }
        return advances.reduce(Money.zero) { $0 + $1.pendingReimbursement }
    }

    /// 編輯與刪除:個人私帳只有本人;家庭共同帳戶是建立者或家庭管理員(上游 ADR 0013、#133)。
    public func canModify(_ account: Account) -> Bool {
        permissions?.current.canModify(account) ?? true
    }

    /// 這張卡在畫面上要脫敏(上游 ADR 0015):他人的個人卡在公帳範圍只看得到家庭代墊待繳額。
    public func isMasked(_ card: CreditCard) -> Bool {
        permissions?.current.isMasked(card) ?? card.isMasked
    }

    /// 公帳範圍裡的個人卡是「私卡代墊」(自己的或他人的)。看的是畫面上已載入的範圍:切換範圍重新載入期間，
    /// 畫面還是舊範圍的內容，念法與標籤要跟著內容走。
    func isPrivateCardAdvance(_ card: CreditCard) -> Bool {
        (freshness.scope ?? scope) == .household && !card.isJointFund
    }

    /// 卡片小字:公帳範圍的個人卡是「私卡代墊・N 日繳」,其他是「家庭公帳／個人私帳・N 日繳」。
    public func caption(for card: CreditCard) -> String {
        isPrivateCardAdvance(card) ? card.advanceCaption() : card.cardCaption
    }

    /// VoiceOver 念的整句。
    public func spokenSummary(of card: CreditCard) -> String {
        isPrivateCardAdvance(card) ? card.spokenAdvanceSummary(isMasked: isMasked(card)) : card.spokenSummary
    }

    /// 信用卡的還款沖銷、出帳作業、校準:個人信用卡只有持卡人;家庭信用卡全員都可以。
    public func canOperate(_ card: CreditCard) -> Bool {
        permissions?.current.canOperate(card) ?? true
    }

    /// 有未出帳款就能做結帳日出帳作業(長按選單)。
    public func showsRollover(_ card: CreditCard) -> Bool {
        canOperate(card) && card.canRollOver
    }

    /// 長按選單的還款項目:他人的個人卡只能繳家庭代墊(上游 ADR 0015、#140);其他卡看有沒有操作權限。
    public func paymentPresets(for card: CreditCard) -> [CardPaymentModel.Preset] {
        if isMasked(card) { return card.sharedDebt > .zero ? [.shared] : [] }
        return canOperate(card) ? card.paymentPresets : []
    }

    /// 例如「確定要將「卡名」的未出帳款 $3,500 轉入本期已出帳待繳款嗎？」,跟詳細頁的一樣。
    public func rolloverConfirmation(for card: CreditCard) -> String {
        card.rolloverConfirmation
    }

    /// 結帳日出帳作業;成功後顯示後端的訊息，並遞增資料版本。
    public func rollOver(_ card: CreditCard) async {
        guard canOperate(card) else { return }
        if let notice = await commit(dataVersion, { try await repository.rollOverStatement(card.id) }) { noticeMessage = notice }
    }

    /// 信用卡扣款還款的 sheet(從信用卡精簡列的長按選單打開):扣款帳戶只列出銀行存款帳戶。
    public func makePayment(for card: CreditCard, preset: CardPaymentModel.Preset) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion,
            isMaskedCard: isMasked(card), today: today
        )
    }

    /// 上一次載入時的資料版本與檢視範圍;跟目前的不同時就要重抓。
    @ObservationIgnored private var freshness = LoadFreshness<AccountScope>()

    /// 畫面的 `.task(id:)` 與 `refreshIfStale()` 共用的重載鍵:檢視範圍或資料版本變了就要重載。
    public var reloadKey: ReloadKey<AccountScope> { ReloadKey(scope: scope, version: dataVersion.value) }

    public func deleteConfirmation(for account: Account) -> String {
        "確定要刪除帳戶「\(account.name)」嗎？這個帳戶的\(Terms.transactions)也會一併刪除！"
    }

    /// 刪除資產帳戶;成功後遞增資料版本(帳戶頁與其他畫面都會重抓)。
    public func delete(_ account: Account) async {
        guard canModify(account) else { return }
        _ = await commit(dataVersion) { try await repository.delete(account.id) }
    }

    /// 資料版本或檢視範圍在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard freshness.isStale(reloadKey) else { return }
        await load()
    }

    /// ATM 提款／帳戶互轉的 sheet。從某個帳戶的按鈕打開時，預先選好轉出或轉入。
    public func makeTransfer(from: AccountID? = nil, to: AccountID? = nil) -> TransferModel {
        TransferModel(repository: repository, dataVersion: dataVersion, today: today, preferredFrom: from, preferredTo: to)
    }

    /// 信用卡詳細頁(點信用卡精簡列 push):跟帳戶頁同一個帳戶檢視範圍，扣款帳戶是這個範圍的銀行存款帳戶。
    public func makeCardDetail(for card: CreditCard) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: bankAccounts, loadedVersion: freshness.version, scope: scope, repository: repository,
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
        let key = reloadKey
        let scope = key.scope
        do {
            async let accounts = repository.accounts(scope: scope)
            async let summary = repository.balanceSummary(scope: scope)
            async let pendingAdvances = fetchPendingAdvanceTotal(for: scope)
            let (loadedAccounts, loadedSummary) = try await (accounts, summary)
            let loadedPendingAdvances = await pendingAdvances
            // 被取消(換了範圍)或已經過期的結果不套用。
            guard !Task.isCancelled, scope == self.scope else { return }
            cashWallets = loadedAccounts.compactMap { if case .cash(let wallet) = $0 { wallet } else { nil } }
            bankAccounts = loadedAccounts.compactMap { if case .bank(let account) = $0 { account } else { nil } }
            creditCards = loadedAccounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            self.summary = loadedSummary
            let memory = skeletonMemory
            memory.record(count: cashWallets.count, for: "cash.\(scope)")
            memory.record(count: bankAccounts.count, for: "bank.\(scope)")
            memory.record(count: creditCards.count, for: "card.\(scope)")
            pendingAdvanceTotal = loadedPendingAdvances
            freshness.markLoaded(key)
            phase = .loaded
            await permissions?.loadIfNeeded()
        } catch {
            // 被取消的載入(換了範圍)不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failure(error)
        }
    }
}

extension AccountKind {
    /// 資產帳戶類型的名稱(CONTEXT.md)。
    public var title: String {
        switch self {
        case .cash: Terms.cash
        case .bank: Terms.bankAccount
        case .creditCard: "信用卡"
        }
    }
}

extension Account {
    /// 帳戶選單項目的副標題：類型加歸屬，例如「現金錢包・個人私帳」。選擇列的值只放名稱，餘額另起一列「可用餘額」
    /// (DESIGN.md「列與欄位」第 7 條，#78)。類型照實標示(web 的週期收支把現金錢包標成「信用卡」,不照抄);
    /// 歸屬寫完整名稱(#150)。
    public var menuSubtitle: String { "\(kind.title)・\(OwnershipName.title(isShared: isJointFund))" }

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
            case .bank: Terms.bankAccount
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
