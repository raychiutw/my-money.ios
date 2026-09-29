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

    public init(
        repository: any AccountRepository,
        dataVersion: DataVersion,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        self.today = today
    }

    /// 有未出帳款就能做結帳日出帳作業，不看結帳日(web 在 `82d9124` 拿掉了結帳日的條件)。
    public func showsRollover(_ card: CreditCard) -> Bool {
        card.unbilledDebt > .zero
    }

    /// 例如「未出帳款 $3,500,可做出帳作業，轉入本期已出帳待繳款」。
    /// web 把「出帳作業」當動詞,iOS 說成「轉入本期已出帳待繳款」(parity 刻意偏離第 41 項)。
    public func rolloverReminder(for card: CreditCard) -> String {
        "未出帳款 \(card.unbilledDebt.formatted()),可做出帳作業，轉入本期已出帳待繳款"
    }

    public func rolloverConfirmation(for card: CreditCard) -> String {
        "確定要將「\(card.name)」的未出帳款 \(card.unbilledDebt.formatted()) 轉入本期已出帳待繳款嗎？"
    }

    /// 結帳日出帳作業;成功後顯示後端的訊息，並遞增資料版本。
    public func rollOver(_ card: CreditCard) async {
        do {
            noticeMessage = try await repository.rollOverStatement(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 正在校準未出帳的信用卡;送出期間停用它的「校準未出帳」。
    public private(set) var reconcilingCardID: AccountID?

    public func isReconciling(_ card: CreditCard) -> Bool {
        reconcilingCardID == card.id
    }

    /// 第一句照 web 的確認文字，改用正名「未出帳款」;接著說明重算的期間、會扣掉刷退和還款。
    /// 後端扣的是還款的全額，繳過已出帳待繳款的話未出帳款會被算少(onion523/my-money#27 第 1 項),
    /// 所以最後提醒(parity 刻意偏離第 39 項)。iOS 不解碼 `last_rollover_at`,只依有沒有結帳日分兩種說法。
    public func reconcileConfirmation(for card: CreditCard) -> String {
        let fallback = card.statementDay == nil ? "算這張卡所有的消費" : "從上一個結帳日起算"
        return "確定要依據「\(card.name)」的當期消費明細，自動校準未出帳款嗎？"
            + "會重算上一次出帳作業之後的消費(還沒做過出帳作業的話，\(fallback)),並扣掉這段期間的刷退和還款。"
            + "這段期間繳過已出帳待繳款的話，未出帳款會被算少。"
    }

    /// 信用卡未出帳自動校準;成功後顯示後端的訊息，並遞增資料版本。
    public func reconcile(_ card: CreditCard) async {
        reconcilingCardID = card.id
        defer { reconcilingCardID = nil }
        do {
            noticeMessage = try await repository.reconcileUnbilled(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 信用卡扣款還款的 sheet(從卡片的「繳家庭代墊」「繳個人私帳」「全額結清」打開):扣款帳戶只列出銀行存款帳戶。
    public func makePayment(for card: CreditCard, preset: CardPaymentModel.Preset) -> CardPaymentModel {
        CardPaymentModel(
            card: card, preset: preset, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion, today: today
        )
    }

    /// 上一次載入時的資料版本與檢視範圍;跟目前的不同時就要重抓。
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: AccountScope?

    public func deleteConfirmation(for account: Account) -> String {
        "確定要刪除帳戶「\(account.name)」嗎？這個帳戶的交易紀錄也會一併刪除！"
    }

    /// 刪除資金帳戶;成功後遞增資料版本(帳戶頁與其他畫面都會重抓)。
    public func delete(_ account: Account) async {
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

    public func makeEditor(adding kind: AccountKind) -> AccountEditorModel {
        AccountEditorModel(adding: kind, repository: repository, dataVersion: dataVersion)
    }

    public func makeEditor(editing account: Account) -> AccountEditorModel {
        AccountEditorModel(editing: account, repository: repository, dataVersion: dataVersion)
    }

    /// 現金錢包的餘額合計;還沒載入時是 `nil`。
    public var cashTotal: Money? { summary?.cashTotal }

    public var cashWalletCountText: String { "\(cashWallets.count) 個現金錢包" }

    /// 銀行存款帳戶的餘額合計;還沒載入時是 `nil`。
    public var bankBalanceTotal: Money? { summary?.bankBalanceTotal }

    public var bankAccountCountText: String { "\(bankAccounts.count) 個銀行存款帳戶" }

    /// 所有信用卡帳戶的待繳卡費總額(已出帳待繳金額加未出帳金額)。
    public var totalCardDue: Money? { summary.map { $0.billedDebtTotal + $0.unbilledDebtTotal } }

    public var billedDebtTotal: Money? { summary?.billedDebtTotal }
    public var unbilledDebtTotal: Money? { summary?.unbilledDebtTotal }

    /// 淨可用資產(後端依帳戶檢視範圍計算)。
    public var availableBalance: Money? { summary?.availableBalance }

    /// 載入這個範圍的資金帳戶與資金指標。重新載入(下拉更新)時保留舊資料，不回到載入中。
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
        } catch {
            // 被取消的載入(換了範圍)不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

extension AccountKind {
    /// 資金帳戶類型的名稱(CONTEXT.md)。
    public var title: String {
        switch self {
        case .cash: "現金錢包"
        case .bank: "銀行存款帳戶"
        case .creditCard: "信用卡"
        }
    }
}

extension Account {
    /// 帳戶選單的文字：名稱加類型，例如「我的皮夾(現金錢包)」(web 的固定收支把現金錢包標成「信用卡」,不照抄)。
    public var menuTitle: String {
        "\(name)(\(kind.title))"
    }

    /// 轉帳和撥款報銷的選單另外帶餘額，例如「我的皮夾(現金錢包，餘額 $1,500)」。這兩個選單沒有信用卡。
    public var menuTitleWithBalance: String {
        switch self {
        case .cash(let wallet): "\(name)(\(kind.title)，餘額 \(wallet.balance.formatted()))"
        case .bank(let bank): "\(name)(\(kind.title)，餘額 \(bank.balance.formatted()))"
        case .creditCard: menuTitle
        }
    }
}

extension ReceivingAccount {
    /// 撥款報銷收款帳戶選單的文字：名稱加類型，不含餘額(其他成員個人私帳的餘額不公開)。
    public var menuTitle: String {
        "\(name)(\(kind.title))"
    }
}
