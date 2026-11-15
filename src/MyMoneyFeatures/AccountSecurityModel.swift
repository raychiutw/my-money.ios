import Foundation
import MyMoneyDomain
import Observation

/// 「我的」→ 帳號安全(#338,與 web 的設定頁對等):登入裝置清單、登出裝置、修改密碼。
/// passkey(#339)之後加在同一個畫面。
@MainActor
@Observable
public final class AccountSecurityModel {
    /// 登入工作階段,後端依最後使用時間排序;載入之前是 `nil`(骨架屏)。
    public private(set) var loginSessions: [LoginSession]?
    /// 清單載入失敗的原因;畫面在那一區顯示它和「重試」。
    public private(set) var sessionsErrorMessage: String?
    /// 登出裝置失敗時的訊息(alert)。
    public var alertMessage: String?

    public var currentPassword = ""
    public var newPassword = ""
    public private(set) var isChangingPassword = false
    /// 修改密碼成功時後端的訊息(「密碼已更新，其他裝置已登出」)。
    public private(set) var passwordChangedMessage: String?
    /// 修改密碼失敗時後端的訊息,例如「目前密碼錯誤」「嘗試次數過多…」。
    public private(set) var passwordErrorMessage: String?

    /// 新密碼的最少字元數(後端 `POST /auth/password` 的規則,web 的表單也這樣擋)。
    public static let minimumPasswordLength = 6

    @ObservationIgnored private let repository: any AccountSecurityRepository

    public init(repository: any AccountSecurityRepository) {
        self.repository = repository
    }

    public var isLoadingSessions: Bool { loginSessions == nil && sessionsErrorMessage == nil }

    /// 有這台以外的裝置時,才能「登出其他所有裝置」。
    public var hasOtherSessions: Bool { loginSessions?.contains { !$0.isCurrent } ?? false }

    public var canChangePassword: Bool {
        !isChangingPassword && !currentPassword.isEmpty && newPassword.count >= Self.minimumPasswordLength
    }

    /// 台灣時間的「yyyy/MM/dd HH:mm」。
    public static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CalendarDay.timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    public func signOutConfirmation(for session: LoginSession) -> String {
        "確定要登出「\(session.deviceName)」嗎？那台裝置需要重新登入。"
    }

    public func load() async {
        do {
            loginSessions = try await repository.loginSessions()
            sessionsErrorMessage = nil
        } catch {
            sessionsErrorMessage = error.localizedDescription
        }
    }

    public func signOut(_ session: LoginSession) async {
        do {
            try await repository.signOut(session.id)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        await load()
    }

    public func signOutOtherSessions() async {
        do {
            try await repository.signOutOtherSessions()
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        await load()
    }

    /// 成功後清空欄位、重新載入清單(其他裝置已被後端登出);這台的權杖不變。
    public func changePassword() async {
        guard canChangePassword else { return }
        isChangingPassword = true
        defer { isChangingPassword = false }
        passwordChangedMessage = nil
        passwordErrorMessage = nil
        do {
            passwordChangedMessage = try await repository.changePassword(current: currentPassword, new: newPassword)
        } catch {
            let message = error.localizedDescription
            passwordErrorMessage = message.isEmpty ? "修改密碼失敗" : message
            return
        }
        currentPassword = ""
        newPassword = ""
        await load()
    }
}
