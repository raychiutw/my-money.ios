import Foundation
import MyMoneyDomain
import Observation

/// 從家庭共同基金撥款報銷代墊款的 sheet(web 的「從共同基金撥款報銷給 {名字}」)。
///
/// 撥款帳戶是家庭共同基金的現金錢包或銀行存款帳戶，不含家庭信用卡(web 在 `da82a11` 也排除了，parity 刻意偏離第 37 項);
/// 收款帳戶是收款成員的可收款帳戶(後端 `b1382f4` 附在代墊統計裡，只有名稱和類型，不含餘額)。
@MainActor
@Observable
public final class ReimbursementModel: Submitting {
    public let advance: HouseholdAdvance
    public private(set) var fundAccounts: [Account] = []
    public let receivingAccounts: [ReceivingAccount]
    public var fromAccountID: AccountID?
    public var toAccountID: AccountID?
    public var amountText: String
    public var date: CalendarDay
    public var note: String

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

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
        receivingAccounts = advance.receivingAccounts
        // 收款帳戶不預選收款成員的第一個可收款帳戶:要使用者自己選(上游 ADR 0011，#113)。
        toAccountID = nil
        amountText = "\(advance.pendingReimbursement.amount)"
        date = today()
        note = "家庭基金撥款報銷 \(advance.memberName) 代墊公帳"
    }

    /// 可用餘額：撥款帳戶(家庭共同基金)的餘額，另起一列顯示(#78)。收款帳戶是其他成員的個人帳戶，餘額不公開。
    public var availableBalance: Money? {
        fundAccounts.first { $0.id == fromAccountID }?.fundsBalance
    }

    public var title: String { "從共同基金撥款報銷給\(advance.memberName)" }

    /// 收款成員沒有可收款帳戶時的說明;這時不能送出。
    public var receivingAccountsNote: String? {
        receivingAccounts.isEmpty ? "\(advance.memberName) 還沒有可收款的個人帳戶(\(Terms.bankAccount)或\(Terms.cash))" : nil
    }

    public var canSubmit: Bool { !receivingAccounts.isEmpty && !isSaving }

    /// 載入撥款帳戶(家庭共同基金)。撥款帳戶與收款帳戶**都不預選**(上游 ADR 0011「顯式帳戶選取」，#113)，要使用者自己選。
    public func load() async {
        do {
            fundAccounts = try await accounts.accounts(scope: .household).filter(Self.holdsMoney)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
    }

    /// 送出;成功時回傳後端的訊息(畫面關閉 sheet 並顯示),並遞增資料版本讓其他畫面重抓。
    public func submit() async -> String? {
        errorMessage = nil
        guard let fromAccountID else {
            errorMessage = "請選擇家庭共同基金帳戶"
            return nil
        }
        guard let toAccountID else {
            errorMessage = "請選擇收款個人帳戶"
            return nil
        }
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請輸入有效的報銷金額"
            return nil
        }
        guard let message = await submitting(failure: "撥款報銷失敗", {
            try await households.reimburse(Reimbursement(
                memberID: advance.memberID, fromAccountID: fromAccountID, toAccountID: toAccountID, amount: amount,
                date: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }) else { return nil }
        dataVersion.bump()
        return message
    }

    private static func holdsMoney(_ account: Account) -> Bool {
        account.fundsBalance != nil
    }
}
