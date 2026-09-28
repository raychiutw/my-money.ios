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
    public private(set) var cashWallets: [CashWallet] = []
    public private(set) var bankAccounts: [BankAccount] = []
    public private(set) var creditCards: [CreditCard] = []
    private var summary: BalanceSummary?

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    /// 操作成功時顯示的訊息(例如結帳日出帳結轉的結果)。
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

    /// 今天(台灣時間)已經到了結帳日，而且有未出帳金額時，提醒結帳日出帳結轉。
    public func showsRollover(_ card: CreditCard) -> Bool {
        card.isStatementDue(today: today())
    }

    /// 例如「每月 15 號結帳日已過，有未出帳金額待結轉」。
    public func rolloverReminder(for card: CreditCard) -> String {
        "每月 \(card.statementDay ?? 0) 號結帳日已過，有未出帳金額待結轉"
    }

    public func rolloverConfirmation(for card: CreditCard) -> String {
        "確定要將「\(card.name)」的未出帳金額 \(card.unbilledDebt.formatted()) 結轉為本期已出帳待繳嗎？"
    }

    /// 結帳日出帳結轉;成功後顯示後端的訊息，並遞增資料版本。
    public func rollOver(_ card: CreditCard) async {
        do {
            noticeMessage = try await repository.rollOverStatement(card.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 信用卡還款沖銷的 sheet:扣款帳戶只列出銀行存款帳戶。
    public func makePayment(for card: CreditCard) -> CardPaymentModel {
        CardPaymentModel(card: card, bankAccounts: bankAccounts, repository: repository, dataVersion: dataVersion, today: today)
    }

    /// 上一次載入時的資料版本;跟目前的版本不同時就要重抓。
    @ObservationIgnored private var loadedVersion: Int?

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

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
        await load()
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

    /// 淨可用資產(後端以整個家庭群組計算)。
    public var availableBalance: Money? { summary?.availableBalance }

    /// 載入資金帳戶與資金指標。重新載入(下拉更新)時保留舊資料，不回到載入中。
    public func load() async {
        let version = dataVersion.value
        do {
            async let accounts = repository.accounts()
            async let summary = repository.balanceSummary()
            let (loadedAccounts, loadedSummary) = try await (accounts, summary)
            cashWallets = loadedAccounts.compactMap { if case .cash(let wallet) = $0 { wallet } else { nil } }
            bankAccounts = loadedAccounts.compactMap { if case .bank(let account) = $0 { account } else { nil } }
            creditCards = loadedAccounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            self.summary = loadedSummary
            loadedVersion = version
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
