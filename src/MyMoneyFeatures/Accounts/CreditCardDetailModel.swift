import Foundation
import MyMoneyDomain
import Observation

/// 信用卡詳細頁的 model(#73,parity.md「帳戶」)。從帳戶頁或總覽的信用卡精簡列 push 進來，由路由建立。
///
/// 繳款、出帳作業、校準未出帳、編輯都在這一頁;成功後資料版本遞增，這一頁、帳戶頁和總覽都重新取得。
@MainActor
@Observable
public final class CreditCardDetailModel {
    /// 目前的信用卡帳戶。
    public private(set) var card: CreditCard

    /// 信用卡扣款還款的扣款帳戶：跟打開這一頁的畫面同一個帳戶檢視範圍的銀行存款帳戶。
    public private(set) var bankAccounts: [BankAccount]

    @ObservationIgnored private let scope: AccountScope
    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
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
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.card = card
        self.bankAccounts = bankAccounts
        self.scope = scope
        self.repository = repository
        self.dataVersion = dataVersion
        self.permissions = permissions
        self.today = today
        if let loadedVersion { freshness.markLoaded(ReloadKey(version: loadedVersion)) }
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
            return [
                CardDetailRow("家庭公帳代墊待繳總額", card.sharedDebt.formatted()),
                CardDetailRow("個人帳單狀態", "隱私遮蔽"),
                CardDetailRow("公帳代墊待清償", card.sharedDebt.formatted()),
                CardDetailRow("個人私帳消費", "隱私遮蔽"),
            ]
        }
        return [
            CardDetailRow("信用卡待繳總額", card.totalDue.formatted()),
            CardDetailRow("已出帳待繳款", card.billedDebt.formatted()),
            CardDetailRow("未出帳款", card.unbilledDebt.formatted()),
            // 欠款公私拆解(畫面上原本叫「負債性質拆解」,section 標題已經表達，不加前綴)。
            CardDetailRow("家庭代墊公帳", card.sharedDebt.formatted()),
            CardDetailRow("個人私帳消費", card.personalDebt.formatted()),
        ]
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

    /// 「操作」區有東西可以顯示:能操作這張卡，或是可以繳家庭代墊。
    public var showsActions: Bool {
        canOperate || !paymentPresets.isEmpty
    }

    /// 有未出帳款、而且能操作這張卡才顯示「出帳作業」。
    public var showsRollover: Bool {
        canOperate && card.canRollOver
    }

    /// 操作失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    /// 操作成功時顯示的訊息(後端回傳的原文)。
    public var noticeMessage: String?

    /// 例如「確定要將「卡名」的未出帳款 $3,500 轉入本期已出帳待繳款嗎？」(#56)。
    public var rolloverConfirmation: String {
        card.rolloverConfirmation
    }

    /// 結帳日出帳作業;成功後顯示後端的訊息，並遞增資料版本(詳細頁、帳戶頁和總覽都重新取得)。
    public func rollOver() async {
        guard canOperate else { return }
        do {
            noticeMessage = try await repository.rollOverStatement(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 正在校準未出帳;送出期間停用「校準未出帳」。
    public private(set) var isReconciling = false

    /// 第一句照 web 的確認文字，改用正名「未出帳款」;接著說明重算的期間、會扣掉刷退，以及還款實際沖到未出帳款的部分。
    /// 後端在上游 `97f4789` 之前已改成只扣還款沖到未出帳款的部分(`unbilled_offset`),不再有「繳過已出帳待繳款就被算少」的問題,
    /// 所以不提醒(parity 刻意偏離第 39 項已刪除)。iOS 不解碼 `last_rollover_at`,只依有沒有結帳日分兩種說法。
    public var reconcileConfirmation: String {
        // 上游 ADR 0020:依結帳區間重算(上一個結帳日之後，加上延至下期的)，不再扣還款沖掉的部分。
        let scope = card.statementDay == nil ? "會重算所有還沒出帳的消費" : "會重算上一個結帳日之後的消費，加上延至下期的消費"
        return "確定要依據「\(card.name)」的當期消費明細，自動校準未出帳款嗎？\(scope)，並扣掉這段期間的刷退。"
    }

    /// 信用卡未出帳自動校準;成功後顯示後端的訊息，並遞增資料版本。
    public func reconcile() async {
        guard canOperate else { return }
        isReconciling = true
        defer { isReconciling = false }
        do {
            noticeMessage = try await repository.reconcileUnbilled(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 信用卡扣款還款的 sheet(「繳款」選單的項目):扣款帳戶是同一個帳戶檢視範圍的銀行存款帳戶。
    public func makePayment(_ preset: CardPaymentModel.Preset) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion,
            isMaskedCard: isMasked, today: today
        )
    }

    /// toolbar 的「編輯」:現有的資產帳戶編輯器。
    public func makeEditor() -> AccountEditorModel {
        AccountEditorModel(editing: .creditCard(card), repository: repository, dataVersion: dataVersion)
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
    /// 有未出帳款就能做結帳日出帳作業，不看結帳日(web 在 `82d9124` 拿掉了結帳日的條件)。
    var canRollOver: Bool {
        unbilledDebt > .zero
    }

    /// 出帳作業的確認。web 把「出帳作業」當動詞,iOS 說成「轉入本期已出帳待繳款」(parity 刻意偏離第 41 項)。
    /// 依結帳區間淨額出帳(上游 ADR 0020):實際轉入多少由後端依結帳日、刷退與延至下期決定，所以不寫金額。
    var rolloverConfirmation: String {
        if let statementDay {
            return "確定要依據「\(name)」的每月結帳日(\(statementDay) 號)，將本期結帳區間內的消費(扣掉刷退，不含延至下期的)轉入本期已出帳待繳款嗎？"
        }
        return "確定要將「\(name)」所有未延期的未出帳消費轉入本期已出帳待繳款嗎？"
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
