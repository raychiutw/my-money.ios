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

/// 設定開關(#299):開啟與關閉都要先驗證成功;裝置不能驗證時不能開;設定依使用者隔離、登出清除。
@MainActor
@Suite("App 鎖的設定開關")
struct AppLockSettingTests {
    private let me = UserID("setting-me")

    private func make(
        capability: DeviceAuthCapability = .faceID, result: DeviceAuthResult = .success
    ) -> (AppLockModel, FakeDeviceAuthenticator) {
        let suite = "AppLockSetting-\(UUID().uuidString)"
        let fake = FakeDeviceAuthenticator(capability: capability, result: result)
        let model = AppLockModel(authenticator: fake, defaults: UserDefaults(suiteName: suite)!)
        model.sessionStarted(userID: me, restored: false)
        return (model, fake)
    }

    @Test("預設是關的;開啟要先驗證成功才生效")
    func enableRequiresAuthentication() async {
        let (model, fake) = make()
        #expect(!model.isEnabled)

        let ok = await model.requestEnabled(true)

        #expect(ok)
        #expect(model.isEnabled)
        #expect(await fake.authenticateCount == 1)
    }

    @Test("開啟時取消或失敗:維持關閉;失敗有說明、取消沒有")
    func enableCancelOrFailureKeepsOff() async {
        let (cancelled, _) = make(result: .cancelled)
        #expect(await cancelled.requestEnabled(true) == false)
        #expect(!cancelled.isEnabled)
        #expect(cancelled.settingMessage == nil)

        let (failed, _) = make(result: .failed)
        #expect(await failed.requestEnabled(true) == false)
        #expect(!failed.isEnabled)
        #expect(failed.settingMessage != nil)
    }

    @Test("關閉也要先驗證成功:取消維持開啟,成功才關")
    func disableRequiresAuthentication() async {
        let (model, fake) = make()
        _ = await model.requestEnabled(true)

        await fake.setResult(.cancelled)
        #expect(await model.requestEnabled(false) == false)
        #expect(model.isEnabled)

        await fake.setResult(.success)
        #expect(await model.requestEnabled(false))
        #expect(!model.isEnabled)
    }

    @Test("裝置沒有生物辨識也沒有密碼:不能開,並說明")
    func cannotEnableWhenUnavailable() async {
        let (model, fake) = make(capability: .unavailable)
        await model.refreshCapability()
        #expect(!model.canEnable)

        #expect(await model.requestEnabled(true) == false)
        #expect(!model.isEnabled)
        #expect(model.settingMessage != nil)
        #expect(await fake.authenticateCount == 0, "不能驗證就不該跳驗證")
    }

    @Test("關閉時裝置已不能驗證(例如移除了密碼):允許關閉,不把人鎖在設定裡")
    func disableAllowedWhenDeviceCannotAuthenticate() async {
        let (model, fake) = make()
        _ = await model.requestEnabled(true)
        await fake.setResult(.unavailable)

        #expect(await model.requestEnabled(false))
        #expect(!model.isEnabled)
    }

    @Test("登出清掉設定;401 過期不清(下次登入還是開著)")
    func signOutClearsButExpiryKeeps() async {
        let (model, _) = make()
        _ = await model.requestEnabled(true)

        model.sessionEnded(clearingSetting: false)
        model.sessionStarted(userID: me, restored: true)
        #expect(model.isEnabled, "過期不清")

        model.sessionEnded(clearingSetting: true)
        model.sessionStarted(userID: me, restored: true)
        #expect(!model.isEnabled, "登出要清")
    }
}

/// 登入後主動詢問是否開啟(#300):第一次登入成功問一次,選什麼都算問過;登出再登入不再問;刪除帳號才重來。
@MainActor
@Suite("登入後詢問是否開啟 App 鎖")
struct AppLockOfferTests {
    private let me = UserID("offer-me")

    private func make(
        capability: DeviceAuthCapability = .faceID, result: DeviceAuthResult = .success
    ) -> (AppLockModel, FakeDeviceAuthenticator) {
        let suite = "AppLockOffer-\(UUID().uuidString)"
        let fake = FakeDeviceAuthenticator(capability: capability, result: result)
        return (AppLockModel(authenticator: fake, defaults: UserDefaults(suiteName: suite)!), fake)
    }

    @Test("第一次登入成功:詢問")
    func offersOnFirstLogin() async {
        let (model, _) = make()
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        #expect(model.shouldOfferEnabling)
    }

    @Test("冷啟動讀回的 session 不問(不是登入)")
    func noOfferOnRestore() async {
        let (model, _) = make()
        model.sessionStarted(userID: me, restored: true)
        await model.evaluateOffer()
        #expect(!model.shouldOfferEnabling)
    }

    @Test("選「開啟」:先驗證成功才生效,而且算問過")
    func acceptEnablesAfterAuthentication() async {
        let (model, fake) = make()
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()

        await model.answerOffer(enable: true)

        #expect(model.isEnabled)
        #expect(!model.shouldOfferEnabling)
        #expect(await fake.authenticateCount == 1)
    }

    @Test("選「暫時不要」:不開、算問過;登出再登入不再問")
    func declineIsAskedOnce() async {
        let (model, _) = make()
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        await model.answerOffer(enable: false)
        #expect(!model.isEnabled)

        model.sessionEnded(clearingSetting: true)
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        #expect(!model.shouldOfferEnabling, "登出再登入不該再問")
    }

    @Test("選「開啟」但驗證取消:沒開成,仍算問過、不再問")
    func cancelledAcceptanceStillCountsAsAsked() async {
        let (model, _) = make(result: .cancelled)
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        await model.answerOffer(enable: true)
        #expect(!model.isEnabled)

        model.sessionEnded()
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        #expect(!model.shouldOfferEnabling)
    }

    @Test("裝置不能驗證:不問;鎖已經開著:不問")
    func noOfferWhenUnavailableOrAlreadyEnabled() async {
        let (unavailable, _) = make(capability: .unavailable)
        unavailable.sessionStarted(userID: me, restored: false)
        await unavailable.evaluateOffer()
        #expect(!unavailable.shouldOfferEnabling)

        let (enabled, _) = make()
        enabled.sessionStarted(userID: me, restored: false)
        enabled.setEnabledWithoutAuthentication(true, for: me)
        await enabled.evaluateOffer()
        #expect(!enabled.shouldOfferEnabling)
    }

    @Test("刪除帳號才清掉「問過」的記號;換使用者各問一次")
    func deletionResetsAndUsersAreIndependent() async {
        let (model, _) = make()
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        await model.answerOffer(enable: false)

        model.sessionStarted(userID: UserID("another"), restored: false)
        await model.evaluateOffer()
        #expect(model.shouldOfferEnabling, "別的使用者各自問一次")
        await model.answerOffer(enable: false)

        model.sessionStarted(userID: me, restored: false)
        model.sessionEnded(clearingSetting: true, forgettingUser: true)
        model.sessionStarted(userID: me, restored: false)
        await model.evaluateOffer()
        #expect(model.shouldOfferEnabling, "刪除帳號之後重來")
    }
}

/// 隱私遮罩(#301):鎖有開時,場景不在作用中(app 切換器)內容要被遮住。
@MainActor
@Suite("App 鎖的隱私遮罩")
struct AppLockPrivacyCoverTests {
    private let me = UserID("cover-me")

    private func make(enabled: Bool) -> AppLockModel {
        let model = AppLockModel(
            authenticator: FakeDeviceAuthenticator(), defaults: UserDefaults(suiteName: "Cover-\(UUID().uuidString)")!
        )
        model.sessionStarted(userID: me, restored: false)
        if enabled { model.setEnabledWithoutAuthentication(true, for: me) }
        return model
    }

    @Test("鎖有開、場景不在作用中:遮住內容")
    func coversWhenInactiveAndEnabled() {
        #expect(make(enabled: true).coversContent(sceneIsActive: false))
    }

    @Test("場景在作用中:不遮")
    func noCoverWhenActive() {
        #expect(!make(enabled: true).coversContent(sceneIsActive: true))
    }

    @Test("鎖沒開:不遮(沒開鎖的人不受影響)")
    func noCoverWhenDisabled() {
        #expect(!make(enabled: false).coversContent(sceneIsActive: false))
    }

    @Test("沒有登入:不遮")
    func noCoverWithoutSession() {
        let model = make(enabled: true)
        model.sessionEnded()
        #expect(!model.coversContent(sceneIsActive: false))
    }
}
