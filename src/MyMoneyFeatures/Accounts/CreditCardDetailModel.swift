import Foundation
import MyMoneyDomain
import Observation

/// 信用卡詳細頁的 model(#73,parity.md「帳戶」)。從帳戶頁或總覽的信用卡精簡列 push 進來，由路由建立。
///
/// 繳款、出帳作業、校準未出帳、編輯都在這一頁;成功後資料版本遞增，這一頁、帳戶頁和總覽都重新取得。
@MainActor
@Observable
public final class CreditCardDetailModel: Alerting {
    /// 目前的信用卡帳戶。
    public private(set) var card: CreditCard

    /// 信用卡扣款還款的扣款帳戶：跟打開這一頁的畫面同一個帳戶檢視範圍的銀行存款帳戶。
    public private(set) var bankAccounts: [BankAccount]

    @ObservationIgnored private let scope: AccountScope
    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let context: SessionContext
    public var dataVersion: DataVersion { context.dataVersion }
    private var today: () -> CalendarDay { context.today }
    @ObservationIgnored private let permissions: PermissionsModel?
    /// 上一次取得時的資料版本;`nil` 是還沒取得過。
    @ObservationIgnored private var freshness = LoadFreshness<Unscoped>()

    /// 畫面的 `.task(id:)` 與 `refreshIfStale()` 共用的重載鍵:資料版本變了就要重載。
    public var reloadKey: ReloadKey<Unscoped> { ReloadKey(version: dataVersion.value) }

    /// `card`、`bankAccounts` 是精簡列所在畫面剛載入的資料,`loadedVersion` 是那次載入的資料版本
    /// (不是現在的：那個畫面可能還在重新載入);`scope` 是那個畫面的帳戶檢視範圍，重新取得時沿用。
    public init(
        card: CreditCard,
        bankAccounts: [BankAccount],
        loadedVersion: Int?,
        scope: AccountScope,
        repository: any AccountRepository,
        permissions: PermissionsModel? = nil,
        context: SessionContext
    ) {
        self.card = card
        self.bankAccounts = bankAccounts
        self.scope = scope
        self.repository = repository
        self.context = context
        self.permissions = permissions
        if let loadedVersion { freshness.markLoaded(ReloadKey(version: loadedVersion)) }
    }

    /// 個別參數的寫法(測試與預覽用),轉成 `SessionContext`。
    public convenience init(
        card: CreditCard,
        bankAccounts: [BankAccount],
        loadedVersion: Int?,
        scope: AccountScope,
        repository: any AccountRepository,
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.init(
            card: card, bankAccounts: bankAccounts, loadedVersion: loadedVersion, scope: scope, repository: repository,
            permissions: permissions, context: SessionContext(dataVersion: dataVersion, today: today)
        )
    }

    /// toolbar 的「編輯」:家庭信用卡只有建立者或家庭管理員，個人信用卡只有持卡人(上游 ADR 0013、#133)。
    public var canEdit: Bool {
        permissions?.current.canModify(.creditCard(card)) ?? true
    }

    /// 繳款、出帳作業、校準未出帳:個人信用卡只有持卡人，家庭信用卡全員都可以。
    public var canOperate: Bool {
        permissions?.current.canOperate(card) ?? true
    }

    /// 這張卡在畫面上要脫敏(上游 ADR 0015):他人的個人卡只看得到家庭代墊待繳額。
    public var isMasked: Bool {
        permissions?.current.isMasked(card) ?? card.isMasked
    }

    /// 「卡費」區塊的各列。脫敏的卡只有家庭代墊是真的，個人帳單與個人消費顯示「隱私遮蔽」。
    public var feeRows: [CardDetailRow] {
        if isMasked {
            // 他人私卡現在揭露已出帳公帳與未出帳公帳(上游 ADR 0025);個人的部分維持遮蔽。
            let revealed = card.debtMatrix.map {
                [
                    CardDetailRow("本期已出帳公帳待繳", $0.billedShared.formatted()),
                    CardDetailRow("未出帳公帳累計", $0.unbilledShared.formatted()),
                ]
            } ?? []
            return [CardDetailRow("家庭公帳代墊待繳總額", card.sharedDebt.formatted())] + revealed + [
                CardDetailRow("個人帳單狀態", "隱私遮蔽"),
                CardDetailRow("公帳代墊待清償", card.sharedDebt.formatted()),
                CardDetailRow("個人私帳消費", "隱私遮蔽"),
            ]
        }
        // 雙層矩陣(上游 ADR 0025):已出帳與未出帳各自列出公帳與私帳;舊的回應沒有矩陣就維持原本的五列。
        let billedSplit = card.debtMatrix.map {
            [CardDetailRow("已出帳公帳", $0.billedShared.formatted()), CardDetailRow("已出帳私帳", $0.billedPersonal.formatted())]
        } ?? []
        let unbilledSplit = card.debtMatrix.map {
            [CardDetailRow("未出帳公帳", $0.unbilledShared.formatted()), CardDetailRow("未出帳私帳", $0.unbilledPersonal.formatted())]
        } ?? []
        return [CardDetailRow("信用卡待繳總額", card.totalDue.formatted()), CardDetailRow("已出帳待繳款", card.billedDebt.formatted())]
            + billedSplit + [CardDetailRow("未出帳款", card.unbilledDebt.formatted())] + unbilledSplit + [
                // 欠款公私拆解(畫面上原本叫「負債性質拆解」,section 標題已經表達，不加前綴)。
                CardDetailRow("家庭代墊公帳", card.sharedDebt.formatted()),
                CardDetailRow("個人私帳消費", card.personalDebt.formatted()),
            ]
    }

    /// 「設定」區塊的預設扣款帳戶(上游 `3d09060`):有綁定而且後端給得出名稱時才有;沒綁定、懸空的綁定(活存帳戶已刪除)、
    /// 脫敏的他人私卡(綁定是對方的私人設定)都沒有。
    public var paymentAccountRow: CardDetailRow? {
        guard !isMasked, let name = card.paymentAccountName else { return nil }
        return CardDetailRow(Terms.defaultPaymentAccount, name)
    }

    /// 「設定」區塊的信用額度與剩餘額度;脫敏的卡不顯示(他人的額度不揭露)。
    /// 沒有設定信用額度時沒有剩餘額度(CONTEXT.md);最小是 0,web 在 82d9124 拿掉了「額度不足」的警示。
    public var limitRows: [CardDetailRow] {
        guard !isMasked else { return [] }
        var rows = [CardDetailRow("信用額度", card.creditLimit?.formatted() ?? "未設定")]
        if let remaining = card.remainingCredit {
            rows.append(CardDetailRow("剩餘額度", remaining.formatted()))
        }
        return rows
    }

    /// 「繳款」的項目。他人的個人卡只能繳家庭代墊(上游 ADR 0015、#140);其他卡看有沒有操作權限。
    public var paymentPresets: [CardPaymentModel.Preset] {
        if isMasked { return card.sharedDebt > .zero ? [.shared] : [] }
        return canOperate ? card.paymentPresets : []
    }

    /// ⋯ 選單的項目,跟帳戶頁的列一樣(`AccountMenuItem`)。
    public var menuItems: [AccountMenuItem] {
        AccountMenuItem.items(
            for: .creditCard(card), canModify: canEdit, canOperate: canOperate, paymentPresets: paymentPresets, showsRollover: showsRollover
        )
    }

    /// 能操作這張卡、而且有結帳日或有款項才顯示「出帳作業」。
    public var showsRollover: Bool {
        canOperate && card.canRollOver
    }

    /// 操作失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    /// 操作成功時顯示的訊息(後端回傳的原文)。
    public var noticeMessage: String?

    /// 這張卡沒設結帳日:按「出帳作業」不開預覽，改請使用者先設定(上游 ADR 0030)。
    public var rolloverNeedsStatementDay: Bool { card.statementDay == nil }

    /// 出帳作業的預覽 sheet(上游 ADR 0024):載入這一期的明細、逐筆決定延至下期，確認後才送出。
    public func makeStatementRollover(locale: Locale = .autoupdatingCurrent) -> StatementRolloverModel {
        StatementRolloverModel(card: card, repository: repository, dataVersion: dataVersion, locale: locale, today: today)
    }

    /// 正在校準未出帳;送出期間停用「校準未出帳」。
    public private(set) var isReconciling = false

    public var reconcileConfirmation: String { card.reconcileConfirmation }

    /// 信用卡未出帳自動校準;成功後顯示後端的訊息，並遞增資料版本。
    public func reconcile() async {
        guard canOperate else { return }
        isReconciling = true
        defer { isReconciling = false }
        if let notice = await commit(dataVersion, { try await repository.reconcileUnbilled(card.id) }) { noticeMessage = notice }
    }

    /// 信用卡扣款還款的 sheet(「繳款」選單的項目):扣款帳戶是同一個帳戶檢視範圍的銀行存款帳戶。
    public func makePayment(_ preset: CardPaymentModel.Preset) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion,
            isMaskedCard: isMasked, today: today
        )
    }

    public var deleteConfirmation: String {
        "確定要刪除帳戶「\(card.name)」嗎？這個帳戶的\(Terms.transactions)也會一併刪除！"
    }

    /// 刪除;成功後遞增資料版本(取得時發現這張卡不見了，畫面回到上一頁)。
    public func delete() async {
        guard canEdit else { return }
        _ = await commit(dataVersion) { try await repository.delete(card.id) }
    }

    /// ⋯ 選單的「編輯」:現有的資產帳戶編輯器。
    public func makeEditor() -> AccountEditorModel {
        AccountEditorModel(editing: .creditCard(card), bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion)
    }

    /// 重新取得時，這張卡已經不在這個帳戶檢視範圍(被刪除，或歸屬改了):畫面回到上一頁。
    public private(set) var isGone = false

    /// 資料版本在上一次取得之後改變過，才重新取得。剛打開時用精簡列的資料，不另外抓。
    public func refreshIfStale() async {
        guard freshness.isStale(reloadKey) else { return }
        await load()
    }

    /// 重新取得這張卡和扣款帳戶。取得失敗時保留目前的內容，顯示錯誤。
    public func load() async {
        let key = reloadKey
        do {
            let accounts = try await repository.accounts(scope: scope)
            guard !Task.isCancelled else { return }
            let cards = accounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            guard let card = cards.first(where: { $0.id == self.card.id }) else {
                isGone = true
                return
            }
            self.card = card
            bankAccounts = accounts.compactMap { if case .bank(let bank) = $0 { bank } else { nil } }
            freshness.markLoaded(key)
        } catch {
            guard !Task.isCancelled else { return }
            alertMessage = error.localizedDescription
        }
    }
}

extension CreditCard {
    /// 第一句照 web 的確認文字，改用正名「未出帳款」;接著說明重算的期間、會扣掉刷退，以及還款實際沖到未出帳款的部分。
    /// 後端在上游 `97f4789` 之前已改成只扣還款沖到未出帳款的部分(`unbilled_offset`),不再有「繳過已出帳待繳款就被算少」的問題,
    /// 所以不提醒(parity 刻意偏離第 39 項已刪除)。iOS 不解碼 `last_rollover_at`,只依有沒有結帳日分兩種說法。
    public var reconcileConfirmation: String {
        // 上游 ADR 0020、`38f0a88`:依結帳區間重算，不再扣還款沖掉的部分;過了結帳日、持卡人還沒手動按「出帳作業」的那一期仍然是未出帳，
        // 所以不說「上一個結帳日之後」(那會漏掉這一期);iOS 不解碼 `last_rollover_at`，不寫出確切的區間。
        let scope = statementDay == nil ? "會重算所有還沒出帳的消費" : "會重算還沒出帳的消費（過了結帳日、還沒按「出帳作業」的那一期也算在內），加上延至下期的消費"
        return "確定要依據「\(name)」的當期消費明細，自動校準未出帳款嗎？\(scope)，並扣掉這段期間的刷退。"
    }

    /// 有結帳日、或有任何已出帳或未出帳的款項，就能打開出帳作業(預覽可以重複檢視，出帳過一次按鈕也不會消失;上游 ADR 0024)。
    var canRollOver: Bool {
        statementDay != nil || unbilledDebt > .zero || billedDebt > .zero
    }

    /// 「繳家庭代墊」的預設金額(上游 ADR 0025):有已出帳公帳就先填它(共同基金只繳當期帳單,不提早繳未出帳的),沒有才填全部公帳。
    var defaultSharedPayment: Money {
        if let matrix = debtMatrix, matrix.billedShared > .zero { return matrix.billedShared }
        return sharedDebt
    }

    /// 已出帳公帳比全部公帳少:繳款畫面才有「僅繳當期已出帳公帳／結清全部代墊公帳」可切換。
    var hasSharedPaymentChoice: Bool {
        guard let matrix = debtMatrix else { return false }
        return matrix.billedShared > .zero && matrix.billedShared < sharedDebt
    }

    /// 「繳款」的項目：繳家庭代墊、繳個人私帳、全額結清，沒有對應欠款的項目隱藏(web 是停用，parity 刻意偏離第 47 項)。
    /// 詳細頁的「繳款」選單和帳戶頁的長按選單共用。
    public var paymentPresets: [CardPaymentModel.Preset] {
        var presets: [CardPaymentModel.Preset] = []
        if sharedDebt > .zero { presets.append(.shared) }
        if personalDebt > .zero { presets.append(.personal) }
        if totalDue > .zero { presets.append(.full) }
        return presets
    }
}

/// 信用卡詳細頁的一列:標題加值(`LabeledContent`)。
public struct CardDetailRow: Identifiable, Hashable, Sendable {
    public let title: String
    public let value: String

    public var id: String { title }

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
}
