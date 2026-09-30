/// 機器人記帳的通訊軟體。raw value 是後端的 `platform`。
public enum BotPlatform: String, Hashable, Sendable {
    case line
    case telegram
}

/// 機器人綁定的 ID,由後端產生。
public struct BotBindingID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 機器人綁定(Bot Binding):通訊軟體帳號跟記帳本帳號的關聯。
public struct BotBinding: Hashable, Sendable, Identifiable {
    public let id: BotBindingID
    public let platform: BotPlatform
    public let displayName: String?

    public init(id: BotBindingID, platform: BotPlatform, displayName: String?) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
    }
}

/// 綁定驗證碼：6 碼大寫英數字，10 分鐘內有效。
public struct PairingCode: Hashable, Sendable {
    public let code: String
    public let expiresInSeconds: Int

    public init(code: String, expiresInSeconds: Int) {
        self.code = code
        self.expiresInSeconds = expiresInSeconds
    }
}

/// 機器人記帳(`/bot`)。
public protocol BotRepository: Sendable {
    /// 產生新的綁定驗證碼;之前的會失效。
    func pairingCode() async throws -> PairingCode

    func bindings() async throws -> [BotBinding]

    func unbind(_ id: BotBindingID) async throws

    /// 模擬對話：送出一則自然語言指令，回傳機器人的回覆。**會寫入真的交易記錄**。
    func simulate(_ text: String) async throws -> String
}
