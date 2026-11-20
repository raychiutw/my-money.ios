import MyMoneyDomain
import Synchronization

/// 存在記憶體裡的 session。同一個 instance 交給新的 `AppSession`,就等於「重開 app」。
///
/// 受生物辨識保護的讀取由假的刷臉結果(`biometricResult`)決定，並記下刷臉幾次(#357)。
public final class InMemorySessionStorage: SessionStorage {
    /// 假刷臉的結果。
    public enum BiometricResult: Sendable {
        case pass
        case cancel
        case fail
        /// 臉部資料變更：保存失效(跟 Keychain 一樣，讀取時就清掉，連同記號)。
        case invalidate
    }

    private struct State {
        var stored: (session: Session, protection: SessionProtection)?
        var biometricResult: BiometricResult
        var biometricPromptCount = 0
        var lastPromptReason: String?
        var keptAfterSignOut: UserID?
        var signedOutByUser = false
    }

    private let state: Mutex<State>
    private let gate: Gate?

    /// - Parameter gate: 給了就讓刷臉停住，直到測試放行(看刷臉期間 session 變了的情況)。
    public init(
        session: Session? = nil, protection: SessionProtection = .standard, biometricResult: BiometricResult = .pass,
        gate: Gate? = nil
    ) {
        state = Mutex(State(stored: session.map { ($0, protection) }, biometricResult: biometricResult))
        self.gate = gate
    }

    public func setBiometricResult(_ result: BiometricResult) {
        state.withLock { $0.biometricResult = result }
    }

    /// 跳過幾次刷臉。
    public var biometricPromptCount: Int {
        state.withLock { $0.biometricPromptCount }
    }

    /// 最近一次刷臉提示的說明。
    public var lastPromptReason: String? {
        state.withLock { $0.lastPromptReason }
    }

    /// 存著的 session 與保護等級(測試直接看存放，不經過刷臉)。
    public var stored: (session: Session, protection: SessionProtection)? {
        state.withLock { $0.stored }
    }

    public func storedProtection() -> SessionProtection? {
        state.withLock { $0.stored?.protection }
    }

    public func storedUser() -> UserID? {
        state.withLock { $0.stored?.session.user.id }
    }

    public func load() -> Session? {
        state.withLock { $0.stored?.protection == .standard ? $0.stored?.session : nil }
    }

    public func loadProtected(reason: String) async -> ProtectedSessionLoad {
        await gate?.pass()
        let prompt: (session: Session, result: BiometricResult)? = state.withLock { state in
            guard let stored = state.stored, stored.protection == .biometric else { return nil }
            state.biometricPromptCount += 1
            state.lastPromptReason = reason
            return (stored.session, state.biometricResult)
        }
        guard let prompt else { return .invalidated }
        switch prompt.result {
        case .pass: return .success(prompt.session)
        case .cancel: return .cancelled
        case .fail: return .failed
        case .invalidate:
            // 跟 Keychain 一樣，失效時 `clear()`:連同記號一起清掉(`Mutex` 不可重入，在鎖外呼叫)。
            clear()
            return .invalidated
        }
    }

    public func save(_ session: Session) {
        state.withLock { $0.stored = (session, $0.stored?.protection ?? .standard) }
    }

    public func save(_ session: Session, protection: SessionProtection) {
        state.withLock { $0.stored = (session, protection) }
    }

    public func clear() {
        state.withLock {
            $0.stored = nil
            $0.keptAfterSignOut = nil
            $0.signedOutByUser = false
        }
    }

    public func keptAfterSignOut() -> UserID? {
        state.withLock { $0.keptAfterSignOut }
    }

    public func setKeptAfterSignOut(_ user: UserID?) {
        state.withLock { $0.keptAfterSignOut = user }
    }

    public func signedOutByUser() -> Bool {
        state.withLock { $0.signedOutByUser }
    }

    public func setSignedOutByUser(_ signedOut: Bool) {
        state.withLock { $0.signedOutByUser = signedOut }
    }
}
