import Foundation

/// 「passkey 驗證器」(#339):用 Face ID／Touch ID 建立新的 passkey(帳號安全)。
/// App 層用 AuthenticationServices 實作,測試用假物件。使用者關掉系統的 passkey 視窗時丟 `CancellationError`。
public protocol PasskeyAuthenticator: Sendable {
    /// 建立:為 `userID`(WebAuthn 的 user handle)產生新的 passkey。
    func registration(relyingPartyID: String, challenge: Data, userID: Data, userName: String) async throws -> PasskeyRegistration
}

/// 驗證器建立的新 passkey(WebAuthn registration 的原始位元組)。
public struct PasskeyRegistration: Equatable, Sendable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

/// 後端的 passkey ID(不是 WebAuthn 的 credential ID)。
public struct PasskeyID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 帳號底下的一個通行金鑰(passkey,GLOSSARY.md)。
public struct Passkey: Hashable, Sendable, Identifiable {
    public let id: PasskeyID
    public let name: String
    public let createdAt: Date
    /// 還沒用來登入過是 `nil`。
    public let lastUsedAt: Date?

    public init(id: PasskeyID, name: String, createdAt: Date, lastUsedAt: Date?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// 帳號安全裡的 passkey 管理(`/auth/passkey/register/*`、`/auth/passkeys`)。
public protocol PasskeyRepository: Sendable {
    /// 新的在前(`GET /auth/passkeys`)。
    func passkeys() async throws -> [Passkey]

    /// 用系統的 passkey 視窗建立一個新的,名稱給後端(空字串時後端用「Passkey」)。使用者取消時丟 `CancellationError`。
    func create(name: String) async throws

    func rename(_ id: PasskeyID, to name: String) async throws

    /// 只停用這個 passkey 之後的登入,不登出已登入的裝置。
    func delete(_ id: PasskeyID) async throws
}
