import Foundation
import MyMoneyDomain
import Observation

/// 一個墊付帳戶底下的待報銷明細(上游 `42149e7`:報銷彈窗依墊付帳戶分組)。名稱相同但類型不同的帳戶是不同的組。
public struct AdvanceGroup: Identifiable, Equatable {
    public struct ID: Hashable, Sendable {
        public let name: String
        public let kind: AccountKind?
    }

    public let id: ID
    public let items: [AdvanceItem]
    /// 這一組已勾選幾筆。
    public let selectedCount: Int

    public var title: String { id.name }
    public var subtotal: Money { items.reduce(.zero) { $0 + $1.amount } }
    public var isFullySelected: Bool { selectedCount == items.count }
}

/// 從家庭共同基金撥款報銷代墊款的 sheet(web 的「從共同基金撥款報銷給 {名字}」)。
///
/// 有待報銷明細時(上游 `d0424df`)逐筆勾選要結清的代墊:預設全選、依墊付帳戶分組、金額是勾選明細的加總、送出帶被勾選的 ID;
/// 沒有明細的待報銷(舊資料)維持手動輸入金額。
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
    /// 勾選要結清的代墊明細 ID(有明細時才有意義)。
    public private(set) var selectedIDs: Set<TransactionID>
    public var date: CalendarDay
    public var note: String

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    @ObservationIgnored private let households: any HouseholdRepository
    @ObservationIgnored private let accounts: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale

    init(
        advance: HouseholdAdvance,
        households: any HouseholdRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay
    ) {
        self.today = today
        self.locale = locale
        self.advance = advance
        self.households = households
        self.accounts = accounts
        self.dataVersion = dataVersion
        receivingAccounts = advance.receivingAccounts
        // 收款帳戶不預選收款成員的第一個可收款帳戶:要使用者自己選(上游 ADR 0011，#113)。
        toAccountID = nil
        amountText = "\(advance.pendingReimbursement.amount)"
        selectedIDs = Set(advance.advanceItems.map(\.id))
        date = today()
        note = "家庭基金撥款報銷 \(advance.memberName) 代墊公帳"
        syncAmount()
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

    public var canSubmit: Bool {
        !receivingAccounts.isEmpty && !isSaving && (!usesItemSelection || !selectedIDs.isEmpty)
    }

    // MARK: 逐筆勾選

    /// 有待報銷明細才逐筆勾選;沒有明細的待報銷(舊資料)維持手動輸入金額。
    public var usesItemSelection: Bool { !advance.advanceItems.isEmpty }

    /// 待報銷明細依墊付帳戶分組，順序照明細第一次出現的順序。
    public var groups: [AdvanceGroup] {
        var order: [AdvanceGroup.ID] = []
        var byGroup: [AdvanceGroup.ID: [AdvanceItem]] = [:]
        for item in advance.advanceItems {
            let id = AdvanceGroup.ID(name: item.accountName, kind: item.accountKind)
            if byGroup[id] == nil { order.append(id) }
            byGroup[id, default: []].append(item)
        }
        return order.map { id in
            let items = byGroup[id] ?? []
            return AdvanceGroup(id: id, items: items, selectedCount: items.filter { selectedIDs.contains($0.id) }.count)
        }
    }

    /// 只有一個墊付帳戶時不需要整組勾選與「僅選此帳戶」。
    public var hasMultipleGroups: Bool { groups.count > 1 }

    /// 勾選明細的加總:報銷金額跟著它走。
    public var selectedAmount: Money {
        advance.advanceItems.filter { selectedIDs.contains($0.id) }.reduce(.zero) { $0 + $1.amount }
    }

    public func isSelected(_ id: TransactionID) -> Bool { selectedIDs.contains(id) }

    /// 勾選清單裡一筆明細的「日期 時間」，跟家庭頁的代墊明細同一個格式，例如「9月27日 03:57」(台灣時間)。
    public func itemDateText(_ item: AdvanceItem) -> String {
        [item.date.text(today: today(), locale: locale), item.recordedAt.map(RecordedTime.clockText(of:))]
            .compactMap { $0 }.joined(separator: " ")
    }

    public func toggle(_ id: TransactionID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        syncAmount()
    }

    /// 整組勾選或取消。
    public func setGroup(_ id: AdvanceGroup.ID, selected: Bool) {
        let ids = advance.advanceItems.filter { AdvanceGroup.ID(name: $0.accountName, kind: $0.accountKind) == id }.map(\.id)
        if selected { selectedIDs.formUnion(ids) } else { selectedIDs.subtract(ids) }
        syncAmount()
    }

    /// 「僅選此帳戶」:清空其他帳戶，只保留這個帳戶的全部。
    public func selectOnly(_ id: AdvanceGroup.ID) {
        selectedIDs = Set(advance.advanceItems.filter { AdvanceGroup.ID(name: $0.accountName, kind: $0.accountKind) == id }.map(\.id))
        syncAmount()
    }

    /// 有明細時金額欄跟著勾選連動(畫面唯讀)。
    private func syncAmount() {
        guard usesItemSelection else { return }
        amountText = "\(selectedAmount.amount)"
    }

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
        let amount: Money
        let advanceIDs: [TransactionID]
        if usesItemSelection {
            guard !selectedIDs.isEmpty else {
                errorMessage = "請至少勾選一筆要報銷的代墊明細"
                return nil
            }
            amount = selectedAmount
            advanceIDs = advance.advanceItems.map(\.id).filter { selectedIDs.contains($0) }
        } else {
            guard let manual = positiveAmount(amountText, label: "報銷金額") else { return nil }
            amount = manual
            advanceIDs = []
        }
        guard let message = await submitting(failure: "撥款報銷失敗", {
            try await households.reimburse(Reimbursement(
                memberID: advance.memberID, fromAccountID: fromAccountID, toAccountID: toAccountID, amount: amount,
                date: date, note: note.trimmingCharacters(in: .whitespacesAndNewlines), advanceIDs: advanceIDs
            ))
        }) else { return nil }
        dataVersion.bump()
        return message
    }

    private static func holdsMoney(_ account: Account) -> Bool {
        account.fundsBalance != nil
    }
}
