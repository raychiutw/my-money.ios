import Foundation
import MyMoneyDomain
import Observation

/// 從家庭共同基金撥款報銷代墊款的 sheet(web 的「從共同基金撥款報銷給 {名字}」)。
///
/// 撥款帳戶是家庭公用的現金錢包或銀行存款帳戶，收款帳戶是我的個人現金錢包或銀行存款帳戶。
/// web 兩邊都沒有排除信用卡;拿信用卡撥款或收款沒有意義，這裡不列出來。
@MainActor
@Observable
public final class ReimbursementModel {
    public let advance: HouseholdAdvance
    public private(set) var fundAccounts: [Account] = []
    public private(set) var receivingAccounts: [Account] = []
    public var fromAccountID: AccountID?
    public var toAccountID: AccountID?
    public var amountText: String
    public var date: CalendarDay
    public var note: String

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    @ObservationIgnored private let households: any HouseholdRepository
    @ObservationIgnored private let accounts: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    init(
        advance: HouseholdAdvance,
        households: any HouseholdRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay
    ) {
        self.advance = advance
        self.households = households
        self.accounts = accounts
        self.dataVersion = dataVersion
        amountText = "\(advance.pendingReimbursement.amount)"
        date = today()
        note = "家庭基金撥款報銷 \(advance.memberName) 代墊公帳"
    }

    public var title: String { "從共同基金撥款報銷給\(advance.memberName)" }

    /// 載入可選的帳戶。撥款帳戶預設第一個餘額夠付待報銷金額的共同基金，沒有就用第一個(web 的 openReimburseModal)。
    public func load() async {
        do {
            async let funds = accounts.accounts(scope: .household)
            async let mine = accounts.accounts(scope: .personal)
            let (loadedFunds, loadedMine) = try await (funds, mine)
            fundAccounts = loadedFunds.filter(Self.holdsMoney)
            receivingAccounts = loadedMine.filter(Self.holdsMoney)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        fromAccountID = (fundAccounts.first { (Self.balance(of: $0) ?? .zero) >= advance.pendingReimbursement } ?? fundAccounts.first)?.id
        toAccountID = receivingAccounts.first?.id
    }

    /// 送出;成功時回傳後端的訊息(畫面關閉 sheet 並顯示),並遞增資料版本讓其他畫面重抓。
    public func submit() async -> String? {
        errorMessage = nil
        guard let fromAccountID, let toAccountID, let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請選擇撥款公帳、收款帳戶並輸入大於 0 的金額"
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let message = try await households.reimburse(Reimbursement(
                memberID: advance.memberID, fromAccountID: fromAccountID, toAccountID: toAccountID, amount: amount,
                date: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            dataVersion.bump()
            return message
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "撥款報銷失敗" : message
            return nil
        }
    }

    /// 選單上的帳戶文字：名稱、類型與目前的餘額。
    private static func holdsMoney(_ account: Account) -> Bool {
        balance(of: account) != nil
    }

    private static func balance(of account: Account) -> Money? {
        switch account {
        case .cash(let wallet): wallet.balance
        case .bank(let bank): bank.balance
        case .creditCard: nil
        }
    }
}
