import Foundation
import MyMoneyDomain
import Observation

/// ATM 提款／帳戶互轉的 sheet(web 的「ATM 提款 / 帳戶轉帳」Modal)。
///
/// 只能在現金錢包和銀行存款帳戶之間轉，信用卡不在選項裡。後端會產生兩筆系統交易記錄，不算生活消費。
@MainActor
@Observable
public final class TransferModel {
    /// 可選的帳戶：現金錢包與銀行存款帳戶，順序照後端。
    public private(set) var candidates: [Account] = []
    public var fromAccountID: AccountID?
    public var toAccountID: AccountID?
    public var amountText = ""
    public var date: CalendarDay
    public var note = ""

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let preferredFrom: AccountID?
    @ObservationIgnored private let preferredTo: AccountID?

    /// `preferredFrom` / `preferredTo`:從某個帳戶的按鈕打開時預先選好的帳戶(現金錢包的「ATM 提款」是轉入，
    /// 銀行存款帳戶的「轉帳／提款」是轉出)。
    public init(
        repository: any AccountRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay = { CalendarDay.today() },
        preferredFrom: AccountID? = nil,
        preferredTo: AccountID? = nil
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        date = today()
        self.preferredFrom = preferredFrom
        self.preferredTo = preferredTo
    }

    /// 可用餘額：轉出帳戶的餘額，另起一列顯示(#78)。
    public var availableBalance: Money? {
        candidates.first { $0.id == fromAccountID }?.fundsBalance
    }

    /// 轉入的選項：不含已選的轉出帳戶。
    public var toCandidates: [Account] {
        candidates.filter { $0.id != fromAccountID }
    }

    /// 兩種快捷情境都需要至少一個銀行存款帳戶和一個現金錢包。
    public var hasQuickScenarios: Bool {
        firstBank != nil && firstWallet != nil
    }

    /// 載入可選的帳戶並套用預設值(web 的 openTransferModal)。
    public func load() async {
        do {
            candidates = try await repository.accounts().filter {
                switch $0 {
                case .cash, .bank: true
                case .creditCard: false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        fromAccountID = preferredFrom ?? firstBank?.id ?? candidates.first?.id
        toAccountID = preferredTo ?? firstWallet?.id ?? candidates.dropFirst().first?.id
        if toAccountID == fromAccountID {
            toAccountID = candidates.first { $0.id != fromAccountID }?.id
        }
    }

    /// 「ATM 提款至皮夾」:第一個銀行存款帳戶轉到第一個現金錢包。
    public func applyATMScenario() {
        guard let bank = firstBank, let wallet = firstWallet else { return }
        fromAccountID = bank.id
        toAccountID = wallet.id
        note = "ATM 提領現鈔至皮夾"
    }

    /// 「存款至銀行」:第一個現金錢包轉到第一個銀行存款帳戶。
    public func applyDepositScenario() {
        guard let bank = firstBank, let wallet = firstWallet else { return }
        fromAccountID = wallet.id
        toAccountID = bank.id
        note = "存入現金至銀行"
    }

    /// 送出;成功時回傳後端的訊息(畫面關閉 sheet 並顯示),並遞增資料版本讓其他畫面重抓。
    public func submit() async -> String? {
        errorMessage = nil
        guard let fromAccountID, let toAccountID, let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請選擇轉出、轉入帳戶，並輸入大於 0 的金額"
            return nil
        }
        guard fromAccountID != toAccountID else {
            errorMessage = "轉出與轉入帳戶不能相同"
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let message = try await repository.transfer(AccountTransfer(
                fromAccountID: fromAccountID, toAccountID: toAccountID, amount: amount, date: date,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            dataVersion.bump()
            return message
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "轉帳失敗" : message
            return nil
        }
    }

    private var firstBank: Account? {
        candidates.first { if case .bank = $0 { true } else { false } }
    }

    private var firstWallet: Account? {
        candidates.first { if case .cash = $0 { true } else { false } }
    }
}
