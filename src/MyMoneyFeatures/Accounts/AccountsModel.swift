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
    public private(set) var bankAccounts: [BankAccount] = []
    public private(set) var creditCards: [CreditCard] = []
    private var summary: BalanceSummary?

    @ObservationIgnored private let repository: any AccountRepository

    public init(repository: any AccountRepository) {
        self.repository = repository
    }

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
        do {
            async let accounts = repository.accounts()
            async let summary = repository.balanceSummary()
            let (loadedAccounts, loadedSummary) = try await (accounts, summary)
            bankAccounts = loadedAccounts.compactMap { if case .bank(let account) = $0 { account } else { nil } }
            creditCards = loadedAccounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            self.summary = loadedSummary
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
