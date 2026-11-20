import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 刷臉讀出受保護的 session 後先換新權杖，再進首頁(#365):更新權杖已失效就直接開登入網頁，不先閃一下首頁。
@MainActor
@Suite("刷臉後先 refresh 再進首頁(#365)")
struct RefreshBeforeHomeTests {
    private let sample = InMemoryAuthRepository.Member.sample.session
    private let rotated = SessionTokens(access: "new-access", refresh: "rotated-refresh", accessExpiresAt: nil)

    /// 刷臉讀出受保護的 session 的兩條路徑。
    enum Path: CaseIterable, Sendable {
        /// 只是關掉 App 的冷啟動：直接刷臉。
        case coldStart
        /// 主動登出後的登入入口頁按「登入」。
        case signInEntry
    }

    /// 存著受保護的 session,停在要刷臉的狀態(根畫面接著呼叫 `unlockProtectedSession`)。
    private func unlocking(_ path: Path, storage: InMemorySessionStorage) -> AppSession {
        if path == .signInEntry {
            storage.setKeptAfterSignOut(sample.user.id)
        }
        let session = AppSession(storage: storage)
        if path == .signInEntry {
            #expect(session.showsSignInEntry)
            session.signInFromEntry()
        }
        #expect(session.isUnlocking)
        return session
    }

    private func boundStorage() -> InMemorySessionStorage {
        InMemorySessionStorage(session: sample, protection: .biometric)
    }

    @Test("刷臉通過、換新成功:進首頁,保存換成新權杖且仍受保護、不再刷臉", arguments: Path.allCases)
    func refreshSucceeds(path: Path) async {
        let storage = boundStorage()
        let session = unlocking(path, storage: storage)
        let auth = InMemoryAuthRepository(members: [.sample], refreshResult: .rotated(rotated), sessionProvider: session)

        await session.unlockProtectedSession(refreshingWith: auth)

        #expect(await auth.refreshCount == 1)
        #expect(!session.isUnlocking)
        #expect(session.current == Session(user: sample.user, tokens: rotated))
        #expect(session.verifiedByBiometrics)
        #expect(storage.stored?.session.tokens == rotated)
        #expect(storage.stored?.protection == .biometric)
        #expect(storage.keptAfterSignOut() == nil)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("刷臉通過、換新被拒(invalid_grant):不進首頁,清除保存與金鑰,開登入網頁", arguments: Path.allCases)
    func refreshRejected(path: Path) async {
        let storage = boundStorage()
        let session = unlocking(path, storage: storage)
        let auth = InMemoryAuthRepository(members: [.sample], refreshResult: .rejected, sessionProvider: session)

        await session.unlockProtectedSession(refreshingWith: auth)

        #expect(await auth.refreshCount == 1)
        #expect(session.current == nil)
        // 未登入、不在解鎖中也不在入口頁:根畫面就是開登入網頁的狀態。
        #expect(!session.isUnlocking)
        #expect(!session.showsSignInEntry)
        #expect(storage.stored == nil)
        #expect(storage.keptAfterSignOut() == nil)
        #expect(await auth.deletedDPoPKey)
        let relaunched = AppSession(storage: storage)
        #expect(!relaunched.isUnlocking)
        #expect(!relaunched.showsSignInEntry)
    }

    @Test("刷臉通過、換新遇到網路錯誤:照樣進首頁,保存不動", arguments: Path.allCases)
    func refreshOffline(path: Path) async {
        let storage = boundStorage()
        let session = unlocking(path, storage: storage)
        let auth = InMemoryAuthRepository(members: [.sample], refreshResult: .offline, sessionProvider: session)

        await session.unlockProtectedSession(refreshingWith: auth)

        #expect(await auth.refreshCount == 1)
        #expect(session.current == sample)
        #expect(storage.stored?.session == sample)
        #expect(storage.stored?.protection == .biometric)
    }

    @Test("刷臉到換新完成之間維持解鎖中的畫面,還不進首頁", .timeLimit(.minutes(1)))
    func staysUnlockingWhileRefreshing() async {
        let storage = boundStorage()
        let session = unlocking(.coldStart, storage: storage)
        let gate = Gate()
        let auth = InMemoryAuthRepository(
            members: [.sample], refreshResult: .rotated(rotated), sessionProvider: session, refreshGate: gate
        )

        let unlocking = Task { await session.unlockProtectedSession(refreshingWith: auth) }
        await gate.waitUntilReached()
        #expect(session.isUnlocking)
        #expect(session.current == nil)
        await gate.open()
        await unlocking.value

        #expect(!session.isUnlocking)
        #expect(session.current?.tokens == rotated)
    }

    @Test("刷臉取消:不換新")
    func cancelledDoesNotRefresh() async {
        let storage = InMemorySessionStorage(session: sample, protection: .biometric, biometricResult: .cancel)
        let session = unlocking(.coldStart, storage: storage)
        let auth = InMemoryAuthRepository(members: [.sample], refreshResult: .rotated(rotated), sessionProvider: session)

        await session.unlockProtectedSession(refreshingWith: auth)

        #expect(await auth.refreshCount == 0)
        #expect(session.current == nil)
    }
}
