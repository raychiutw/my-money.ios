import MyMoneyDomain
import Synchronization

/// 站在 app 那一側的 session:提供 token,並記下翻譯層通知了幾次「session 過期」。
final class FakeSessionProvider: SessionProvider {
    private let token: String?
    private let expirations = Mutex(0)

    init(token: String? = nil) {
        self.token = token
    }

    var expirationCount: Int {
        expirations.withLock { $0 }
    }

    func currentToken() async -> String? {
        token
    }

    func sessionDidExpire() async {
        expirations.withLock { $0 += 1 }
    }
}
