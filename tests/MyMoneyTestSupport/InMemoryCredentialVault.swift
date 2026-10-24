import MyMoneyDomain
import Synchronization

/// 測試與 `-uiTesting` 用的帳密保管箱:放在記憶體裡。
public final class InMemoryCredentialVault: CredentialVault {
    private let stored = Mutex<SavedCredentials?>(nil)

    public init(saved: SavedCredentials? = nil) { stored.withLock { $0 = saved } }

    public func hasSaved() -> Bool { stored.withLock { $0 != nil } }
    public func save(_ credentials: SavedCredentials) { stored.withLock { $0 = credentials } }
    public func load() -> SavedCredentials? { stored.withLock { $0 } }
    public func delete() { stored.withLock { $0 = nil } }
}
