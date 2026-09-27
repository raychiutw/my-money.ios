import MyMoneyDomain
import Synchronization

/// 存在記憶體裡的 session。同一個 instance 交給新的 `AppSession`,就等於「重開 app」。
public final class InMemorySessionStorage: SessionStorage {
    private let stored: Mutex<Session?>

    public init(session: Session? = nil) {
        stored = Mutex(session)
    }

    public func load() -> Session? {
        stored.withLock { $0 }
    }

    public func save(_ session: Session) {
        stored.withLock { $0 = session }
    }

    public func clear() {
        stored.withLock { $0 = nil }
    }
}
