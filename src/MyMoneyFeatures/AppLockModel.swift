import Foundation
import MyMoneyDomain
import Observation

/// App 鎖(#297、#298):這支手機上的生物辨識鎖,純本機,不碰後端與 session。
///
/// 規則:鎖有開、而且有登入——冷啟動(讀回上次的 session)就鎖;離開 app 滿寬限時間(60 秒)再回來才鎖;
/// 剛輸入密碼登入成功不鎖。驗證成功才解鎖;取消或失敗維持鎖定、可以再試;驗證當下裝置已經不能驗證就直接解鎖
/// (不把人鎖在外面)。驗證失敗**不登出、不清 token**。
@MainActor
@Observable
public final class AppLockModel {
    public enum LockState: Equatable, Sendable {
        case unlocked
        case locked
        case authenticating
    }

    public private(set) var state: LockState = .unlocked
    /// 上一次驗證失敗時給人看的說明;取消不算失敗,沒有說明。
    public private(set) var failureMessage: String?
    /// 目前登入的人;沒有登入是 `nil`。
    public private(set) var userID: UserID?

    public var isLocked: Bool { state != .unlocked }

    /// 這支裝置能用的驗證方式(鎖畫面寫「Face ID」「Touch ID」…);還沒查過是 `nil`。
    public private(set) var capability: DeviceAuthCapability?

    /// 第一次登入成功後要不要跳出「要不要開啟」的詢問(#300);登入頁之後的畫面依它顯示。
    public private(set) var shouldOfferEnabling = false

    /// 設定頁的說明:不能開啟(裝置沒有可用的驗證)或驗證失敗時的訊息;沒事是 `nil`。
    public private(set) var settingMessage: String?

    /// 這支裝置能不能開鎖(有生物辨識或裝置密碼);還沒查過時先當作可以(設定頁會先查)。
    public var canEnable: Bool { capability?.isAvailable ?? true }

    /// 例如「Face ID」;沒有生物辨識寫「裝置密碼」。還沒查過時是通用的「Face ID 或裝置密碼」。
    public var unlockMethodName: String {
        switch capability {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcodeOnly, .unavailable: "裝置密碼"
        case nil: "Face ID 或裝置密碼"
        }
    }

    /// 查這支裝置能用哪一種驗證(鎖畫面出現與設定頁用)。
    public func refreshCapability() async {
        capability = await authenticator.capability()
    }

    /// 離開 app 滿這麼多秒再回來才鎖(預設值;UI 測試可以縮短)。
    public static let gracePeriod: TimeInterval = 60
    @ObservationIgnored private let graceSeconds: TimeInterval

    @ObservationIgnored private let authenticator: any DeviceAuthenticator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    /// 設定存在 UserDefaults(不是可觀察的),寫入時遞增這個數字,讀設定的畫面才會跟著更新(#299)。
    private var settingRevision = 0
    @ObservationIgnored private var backgroundedAt: Date?
    /// 這次登入是剛輸入密碼登入的(不是讀回 session):才有資格被詢問。
    @ObservationIgnored private var isFreshLogin = false

    public init(
        authenticator: any DeviceAuthenticator, defaults: UserDefaults, now: @escaping () -> Date = { Date() },
        gracePeriod: TimeInterval = AppLockModel.gracePeriod
    ) {
        graceSeconds = gracePeriod
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
    }

    // MARK: 設定(只存本機,依使用者隔離)

    /// 這位使用者有沒有開鎖。
    public func isEnabled(for userID: UserID) -> Bool {
        _ = settingRevision
        return defaults.bool(forKey: Self.key(userID))
    }

    /// 目前登入的人有沒有開鎖。
    public var isEnabled: Bool { userID.map(isEnabled(for:)) ?? false }

    /// 不經驗證直接寫入設定:給 UI 測試的啟動旗標與設定頁驗證成功之後用。
    public func setEnabledWithoutAuthentication(_ enabled: Bool, for userID: UserID) {
        defaults.set(enabled, forKey: Self.key(userID))
        settingRevision += 1
    }

    /// 設定頁的開關:**開啟與關閉都要先驗證成功一次**才變更。裝置不能驗證時不能開(並說明);
    /// 關閉時裝置已不能驗證就允許關(不把人鎖在設定裡)。回傳這次有沒有變更成功。
    @discardableResult
    public func requestEnabled(_ enabled: Bool) async -> Bool {
        guard let userID else { return false }
        settingMessage = nil
        if enabled {
            await refreshCapability()
            guard canEnable else {
                settingMessage = "這支手機還沒有設定 Face ID 或裝置密碼，請先到「設定」開啟。"
                return false
            }
        }
        switch await authenticator.authenticate(reason: enabled ? "開啟 App 鎖" : "關閉 App 鎖") {
        case .success:
            break
        case .unavailable:
            // 開啟時不能驗證:不開;關閉時只有裝置真的沒有任何驗證方式才允許(不能靠錯誤碼繞過)。
            guard !enabled else {
                settingMessage = "這支手機目前不能驗證，無法開啟。"
                return false
            }
            await refreshCapability()
            guard capability?.isAvailable == false else {
                settingMessage = "驗證失敗，設定沒有變更。"
                return false
            }
        case .cancelled:
            return false
        case .failed:
            settingMessage = "驗證失敗，設定沒有變更。"
            return false
        }
        setEnabledWithoutAuthentication(enabled, for: userID)
        return true
    }

    // MARK: 隱私遮罩(#301)

    /// 鎖有開、有登入、場景不在作用中(app 切換器、通知中心等)時,內容要被遮住。
    public func coversContent(sceneIsActive: Bool) -> Bool {
        !sceneIsActive && isEnabled
    }

    // MARK: 登入後詢問(只問一次)

    /// 第一次登入成功之後:裝置能驗證、鎖還沒開、這位使用者還沒被問過,才要詢問。
    public func evaluateOffer() async {
        guard isFreshLogin, let userID, !isEnabled(for: userID), !defaults.bool(forKey: Self.askedKey(userID)) else { return }
        await refreshCapability()
        guard canEnable else { return }
        shouldOfferEnabling = true
    }

    /// 詢問框一關掉就同步隱藏(不等回答的非同步工作做完,避免重複彈出)。
    public func hideOffer() {
        shouldOfferEnabling = false
    }

    /// 回答詢問:**不管選什麼都算問過**(只問一次);選「開啟」要先驗證成功才生效。
    public func answerOffer(enable: Bool) async {
        guard let userID else { return }
        defaults.set(true, forKey: Self.askedKey(userID))
        shouldOfferEnabling = false
        isFreshLogin = false
        if enable { await requestEnabled(true) }
    }

    private static func askedKey(_ userID: UserID) -> String { "appLock.asked.\(userID.rawValue)" }

    private static func key(_ userID: UserID) -> String { "appLock.enabled.\(userID.rawValue)" }

    // MARK: session

    /// 開始(或讀回)一個 session。`restored` 是冷啟動讀回上次存下的 session;剛登入成功是 `false`,不鎖。
    public func sessionStarted(userID: UserID, restored: Bool) {
        self.userID = userID
        failureMessage = nil
        backgroundedAt = nil
        isFreshLogin = !restored
        shouldOfferEnabling = false
        state = restored && isEnabled(for: userID) ? .locked : .unlocked
    }

    /// session 結束(登出、刪除帳號、401):沒有東西好鎖,解開鎖並回到登入頁。
    /// `clearingSetting`:登出與刪除帳號清掉這位使用者的鎖設定;401 過期不清,下次登入還是開著。
    /// `forgettingUser`:刪除帳號才清掉「已經問過要不要開啟」的記號(#300);登出再登入不會再問。
    public func sessionEnded(clearingSetting: Bool = false, forgettingUser: Bool = false) {
        if clearingSetting, let userID {
            defaults.removeObject(forKey: Self.key(userID))
            settingRevision += 1
        }
        if forgettingUser, let userID { defaults.removeObject(forKey: Self.askedKey(userID)) }
        userID = nil
        isFreshLogin = false
        shouldOfferEnabling = false
        failureMessage = nil
        backgroundedAt = nil
        state = .unlocked
    }

    // MARK: 場景

    public func enteredBackground() {
        backgroundedAt = now()
    }

    /// 回到前景:鎖有開、有登入、離開滿寬限時間才鎖。
    public func becameActive() {
        defer { backgroundedAt = nil }
        guard let backgroundedAt, isEnabled, state == .unlocked else { return }
        if now().timeIntervalSince(backgroundedAt) >= graceSeconds {
            state = .locked
        }
    }

    // MARK: 解鎖

    /// 跳出系統驗證:成功解鎖;取消維持鎖定;失敗維持鎖定並說明;裝置已不能驗證就直接解鎖。
    public func unlock() async {
        guard state == .locked else { return }
        state = .authenticating
        failureMessage = nil
        switch await authenticator.authenticate(reason: "解鎖「我的記帳本」") {
        case .success:
            state = .unlocked
        case .unavailable:
            // 只有裝置真的沒有生物辨識也沒有密碼才放行(不把人鎖在外面);不能只靠錯誤碼——
            // 例如對本 app 拒絕了 Face ID 也會回「不可用」,那不能當成通過(code review)。
            await refreshCapability()
            if capability?.isAvailable == false {
                state = .unlocked
            } else {
                state = .locked
                failureMessage = "驗證失敗，請再試一次"
            }
        case .cancelled:
            state = .locked
        case .failed:
            state = .locked
            failureMessage = "驗證失敗，請再試一次"
        }
    }
}
