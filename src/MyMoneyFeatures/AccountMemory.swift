import Foundation
import MyMoneyDomain

/// 記住的帳戶(#273):每個「選帳戶」的功能各自記住上次選的帳戶，下次新增時帶入。只存在這支裝置，不送後端。
///
/// 這是對上游 ADR 0011「顯式帳戶選取」的刻意偏離(`docs/parity.md`):預選的是使用者自己上次的選擇，仍可改選、仍必填。
/// key 綁登入的使用者，換人登入不沿用。記住的帳戶已不在可選清單(刪除、看不到)就當作沒有，欄位照舊空白。
public struct AccountMemory {
    /// 哪一個「選帳戶」的功能;每個各一個 key。
    public enum Purpose: String, CaseIterable, Sendable {
        case quickEntry
        case transferFrom
        case transferTo
        case cardPaymentBank
        case reimbursementFund
        case reimbursementReceiving
        case recurring
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, userID: UserID, purpose: Purpose) {
        self.defaults = defaults
        key = "accountMemory.\(userID.rawValue).\(purpose.rawValue)"
    }

    /// 記住的帳戶,而且還在 `accounts` 裡;沒記過或已不在清單是 `nil`。
    public func recall(among accounts: [Account]) -> AccountID? {
        recall(amongIDs: accounts.map(\.id))
    }

    /// 同上,可選清單不是 `Account`(例如收款成員的可收款帳戶)時用。
    public func recall(amongIDs ids: [AccountID]) -> AccountID? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        let id = AccountID(raw)
        return ids.contains(id) ? id : nil
    }

    /// 值和已記的一樣就不寫(同 `ScopeMemory`)。
    public func remember(_ id: AccountID) {
        guard defaults.string(forKey: key) != id.rawValue else { return }
        defaults.set(id.rawValue, forKey: key)
    }
}
