import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// App 鎖(#298、#297):冷啟動鎖、離開超過寬限時間回來才鎖、取消或失敗維持鎖定、未登入不鎖、登入成功不鎖。
@MainActor
@Suite("App 鎖")
struct AppLockTests {
    private let suite = "AppLockTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let me = UserID("lock-me")

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func make(
        enabled: Bool = true, authenticator: FakeDeviceAuthenticator = FakeDeviceAuthenticator(), clock: Clock = Clock()
    ) -> (AppLockModel, FakeDeviceAuthenticator, Clock) {
        let defaults = defaults
        defaults.removePersistentDomain(forName: suite)
        let model = AppLockModel(authenticator: authenticator, defaults: defaults, now: { clock.now })
        if enabled { model.setEnabledWithoutAuthentication(true, for: me) }
        return (model, authenticator, clock)
    }

    @Test("冷啟動(讀回上次的 session)且鎖有開:鎖定")
    func coldStartLocksWhenEnabled() {
        let (model, _, _) = make()
        model.sessionStarted(userID: me, restored: true)
        #expect(model.state == .locked)
        #expect(model.isLocked)
    }

    @Test("冷啟動但鎖沒開:不鎖")
    func coldStartDoesNotLockWhenDisabled() {
        let (model, _, _) = make(enabled: false)
        model.sessionStarted(userID: me, restored: true)
        #expect(model.state == .unlocked)
    }

    @Test("剛輸入密碼登入成功:不鎖,不用再驗一次")
    func freshLoginDoesNotLock() {
        let (model, _, _) = make()
        model.sessionStarted(userID: me, restored: false)
        #expect(model.state == .unlocked)
    }

    @Test("驗證成功:解鎖")
    func unlockSucceeds() async {
        let (model, fake, _) = make()
        model.sessionStarted(userID: me, restored: true)

        await model.unlock()

        #expect(model.state == .unlocked)
        #expect(await fake.authenticateCount == 1)
    }

    @Test("取消:維持鎖定、沒有失敗訊息,可以再試")
    func cancelStaysLocked() async {
        let (model, fake, _) = make(authenticator: FakeDeviceAuthenticator(result: .cancelled))
        model.sessionStarted(userID: me, restored: true)

        await model.unlock()
        #expect(model.state == .locked)
        #expect(model.failureMessage == nil)

        await fake.setResult(.success)
        await model.unlock()
        #expect(model.state == .unlocked)
    }

    @Test("驗證失敗:維持鎖定並說明,而且不登出(鎖不碰 session)")
    func failureStaysLockedWithMessage() async {
        let (model, _, _) = make(authenticator: FakeDeviceAuthenticator(result: .failed))
        model.sessionStarted(userID: me, restored: true)

        await model.unlock()

        #expect(model.state == .locked)
        #expect(model.failureMessage != nil)
    }

    @Test("驗證當下裝置已不能驗證(例如移除了裝置密碼):不把人鎖在外面,直接解鎖")
    func unavailableUnlocks() async {
        let (model, _, _) = make(authenticator: FakeDeviceAuthenticator(result: .unavailable))
        model.sessionStarted(userID: me, restored: true)

        await model.unlock()

        #expect(model.state == .unlocked)
    }

    @Test("離開 app 不到寬限時間(60 秒)回來:不鎖;滿 60 秒才鎖")
    func graceWindow() {
        let (model, _, clock) = make()
        model.sessionStarted(userID: me, restored: false)

        model.enteredBackground()
        clock.now += 59
        model.becameActive()
        #expect(model.state == .unlocked, "59 秒不鎖")

        model.enteredBackground()
        clock.now += 60
        model.becameActive()
        #expect(model.state == .locked, "滿 60 秒要鎖")
    }

    @Test("鎖沒開:離開再久也不鎖")
    func disabledNeverLocks() {
        let (model, _, clock) = make(enabled: false)
        model.sessionStarted(userID: me, restored: false)
        model.enteredBackground()
        clock.now += 3600
        model.becameActive()
        #expect(model.state == .unlocked)
    }

    @Test("沒有登入(沒有 session):不鎖;鎖著時 session 結束(登出、401)就解開,回到登入頁")
    func noSessionNoLock() {
        let (model, _, clock) = make()
        model.enteredBackground()
        clock.now += 3600
        model.becameActive()
        #expect(model.state == .unlocked, "沒有 session 不鎖")

        model.sessionStarted(userID: me, restored: true)
        #expect(model.state == .locked)
        model.sessionEnded()
        #expect(model.state == .unlocked)
    }

    @Test("鎖的設定依使用者隔離:別人登入不會被鎖")
    func perUser() {
        let (model, _, _) = make()
        model.sessionStarted(userID: UserID("someone-else"), restored: true)
        #expect(model.state == .unlocked)
    }
}

@MainActor
@Suite("App 鎖的解鎖方式名稱")
struct AppLockMethodNameTests {
    @Test("依裝置寫 Face ID、Touch ID、Optic ID 或裝置密碼;還沒查過是通用說法")
    func names() async {
        let suite = "AppLockNames-\(UUID().uuidString)"
        let fake = FakeDeviceAuthenticator(capability: .touchID)
        let model = AppLockModel(authenticator: fake, defaults: UserDefaults(suiteName: suite)!)
        #expect(model.unlockMethodName == "Face ID 或裝置密碼")

        await model.refreshCapability()
        #expect(model.unlockMethodName == "Touch ID")
        await fake.setCapability(.faceID)
        await model.refreshCapability()
        #expect(model.unlockMethodName == "Face ID")
        await fake.setCapability(.passcodeOnly)
        await model.refreshCapability()
        #expect(model.unlockMethodName == "裝置密碼")
    }
}
