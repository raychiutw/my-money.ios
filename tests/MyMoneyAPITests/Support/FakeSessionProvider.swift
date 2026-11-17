import Foundation
import MyMoneyDomain
import Synchronization

/// 站在 app 那一側的 session:提供權杖,記下翻譯層通知了幾次「session 過期」,並保存 refresh 輪替後的權杖。
final class FakeSessionProvider: SessionProvider {
    private let state: Mutex<(tokens: SessionTokens?, expirations: Int)>

    /// 只有存取權杖、沒有到期時間(一般請求的測試)。
    convenience init(token: String? = nil) {
        self.init(tokens: token.map { SessionTokens(access: $0, refresh: "fake-refresh", accessExpiresAt: nil) })
    }

    init(tokens: SessionTokens?) {
        state = Mutex((tokens, 0))
    }

    var expirationCount: Int {
        state.withLock { $0.expirations }
    }

    /// 目前的權杖(refresh 輪替後是新的);過期後是 `nil`。
    var tokens: SessionTokens? {
        state.withLock { $0.tokens }
    }

    /// app 那一側登出了(例如 Face ID 登入的人登出、保留 session,#364):之後沒有權杖,不算過期。
    func endSession() {
        state.withLock { $0.tokens = nil }
    }

    func currentTokens() async -> SessionTokens? {
        tokens
    }

    func sessionDidRefresh(_ tokens: SessionTokens, replacing previousRefresh: String) async {
        state.withLock { $0.tokens = tokens }
    }

    func sessionDidExpire(refresh: String) async -> Bool {
        state.withLock {
            guard $0.tokens?.refresh == refresh else { return false }
            $0.tokens = nil
            $0.expirations += 1
            return true
        }
    }
}
