/// 登入用的帳號與密碼(Face ID 登入存的那一份)。
public struct SavedCredentials: Equatable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

/// 存放「用 Face ID 登入」的帳密(#308)。真實實作把它放在 Keychain(只限這支裝置、要設了裝置密碼才存得進去),
/// 測試用 `MyMoneyTestSupport` 的記憶體版本。讀取前由呼叫端先驗證本人(`DeviceAuthenticator`)。
public protocol CredentialVault: Sendable {
    func hasSaved() -> Bool
    /// 回傳有沒有存成功(例如裝置沒設密碼就存不進去)。
    @discardableResult
    func save(_ credentials: SavedCredentials) -> Bool
    func load() -> SavedCredentials?
    func delete()
}

extension SavedCredentials {
    /// 是不是同一個帳號:後端的 Email 不分大小寫,這裡也不分。
    public func isAccount(email other: String?) -> Bool {
        other.map { email.caseInsensitiveCompare($0) == .orderedSame } ?? false
    }
}
