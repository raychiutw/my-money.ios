import MyMoneyDomain
import Synchronization

/// 測試與 `-uiTesting` 用的帳密保管箱:放在記憶體裡。`failsToSave` 模擬 Keychain 寫入失敗(例如沒設裝置密碼)。
public final class InMemoryCredentialVault: CredentialVault {
    private let stored = Mutex<SavedCredentials?>(nil)
    private let failsToSave: Bool

    public init(saved: SavedCredentials? = nil, failsToSave: Bool = false) {
        self.failsToSave = failsToSave
        stored.withLock { $0 = saved }
    }

    public func hasSaved() -> Bool { stored.withLock { $0 != nil } }
    public func load() -> SavedCredentials? { stored.withLock { $0 } }
    public func delete() { stored.withLock { $0 = nil } }

    @discardableResult
    public func save(_ credentials: SavedCredentials) -> Bool {
        guard !failsToSave else { return false }
        stored.withLock { $0 = credentials }
        return true
    }
}
