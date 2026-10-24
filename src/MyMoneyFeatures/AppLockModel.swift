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

    /// 離開 app 滿這麼多秒再回來才鎖。
    public static let gracePeriod: TimeInterval = 60

    @ObservationIgnored private let authenticator: any DeviceAuthenticator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var backgroundedAt: Date?

    public init(authenticator: any DeviceAuthenticator, defaults: UserDefaults, now: @escaping () -> Date = { Date() }) {
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
    }

    // MARK: 設定(只存本機,依使用者隔離)

    /// 這位使用者有沒有開鎖。
    public func isEnabled(for userID: UserID) -> Bool {
        defaults.bool(forKey: Self.key(userID))
    }

    /// 目前登入的人有沒有開鎖。
    public var isEnabled: Bool { userID.map(isEnabled(for:)) ?? false }

    /// 不經驗證直接寫入設定:給 UI 測試的啟動旗標與設定頁驗證成功之後用。
    public func setEnabledWithoutAuthentication(_ enabled: Bool, for userID: UserID) {
        defaults.set(enabled, forKey: Self.key(userID))
    }

    private static func key(_ userID: UserID) -> String { "appLock.enabled.\(userID.rawValue)" }

    // MARK: session

    /// 開始(或讀回)一個 session。`restored` 是冷啟動讀回上次存下的 session;剛登入成功是 `false`,不鎖。
    public func sessionStarted(userID: UserID, restored: Bool) {
        self.userID = userID
        failureMessage = nil
        backgroundedAt = nil
        state = restored && isEnabled(for: userID) ? .locked : .unlocked
    }

    /// session 結束(登出、刪除帳號、401):沒有東西好鎖,解開鎖並回到登入頁。
    public func sessionEnded() {
        userID = nil
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
        if now().timeIntervalSince(backgroundedAt) >= Self.gracePeriod {
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
        case .success, .unavailable:
            state = .unlocked
        case .cancelled:
            state = .locked
        case .failed:
            state = .locked
            failureMessage = "驗證失敗,請再試一次"
        }
    }
}
