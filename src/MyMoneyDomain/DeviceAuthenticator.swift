/// 這支裝置能用哪一種方式驗證本人(#298):生物辨識、只有裝置密碼、或都沒有。
public enum DeviceAuthCapability: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// 沒有生物辨識，但設了裝置密碼。
    case passcodeOnly
    /// 沒有生物辨識也沒有裝置密碼:不能用 app 鎖。
    case unavailable

    public var isAvailable: Bool { self != .unavailable }
}

/// 一次驗證的結果。
public enum DeviceAuthResult: Equatable, Sendable {
    case success
    /// 使用者取消(或系統取消):不是錯誤，畫面維持鎖定、可以再試。
    case cancelled
    /// 驗證失敗(辨識不符、被鎖住又沒通過密碼等)。
    case failed
    /// 驗證當下裝置已經不能驗證(例如移除了裝置密碼)。
    case unavailable
}

/// 驗證本人的介面(生物辨識為主，失敗可改用裝置密碼)。真實實作在 composition root(系統的 LocalAuthentication),
/// 測試用 `MyMoneyTestSupport` 的假驗證器。純本機、不碰後端(#297)。
public protocol DeviceAuthenticator: Sendable {
    func capability() async -> DeviceAuthCapability
    /// 跳出系統的驗證提示;`reason` 是給人看的說明(繁體中文)。
    func authenticate(reason: String) async -> DeviceAuthResult
}
