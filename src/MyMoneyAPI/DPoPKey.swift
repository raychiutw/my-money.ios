import CryptoKit
import Foundation

/// 綁定登入工作階段的 DPoP 金鑰(RFC 9449,上游 ADR 0039,#337):P-256 ES256。
/// 實機的私鑰在 Secure Enclave,拿不出來;只能用它簽 proof。
public struct DPoPKey: Sendable {
    public let publicKey: P256.Signing.PublicKey
    /// 存進 Keychain 的內容:軟體金鑰是私鑰本身,Secure Enclave 金鑰是加密過的參照。
    let storedRepresentation: Data
    private let signer: @Sendable (Data) throws -> P256.Signing.ECDSASignature

    /// 軟體金鑰:模擬器(沒有 Secure Enclave)與測試用。
    public init(_ privateKey: P256.Signing.PrivateKey) {
        publicKey = privateKey.publicKey
        storedRepresentation = privateKey.rawRepresentation
        signer = { try privateKey.signature(for: $0) }
    }

    /// Secure Enclave 金鑰:實機用。
    public init(_ privateKey: SecureEnclave.P256.Signing.PrivateKey) {
        publicKey = privateKey.publicKey
        storedRepresentation = privateKey.dataRepresentation
        signer = { try privateKey.signature(for: $0) }
    }

    /// JWS 的 ES256 簽章是 r||s(64 bytes),不是 DER。
    func sign(_ data: Data) throws -> Data {
        try signer(data).rawRepresentation
    }
}

/// DPoP 金鑰存放的地方:每次登入換一把新的(換碼成功才取代);登出、`invalid_grant`、刪除帳號時刪掉。
public protocol DPoPKeyStore: Sendable {
    /// 目前這個登入工作階段的金鑰;沒有時是 `nil`(請求改用沒有綁定的 `Bearer`)。
    func load() -> DPoPKey?

    /// 產生一把新的金鑰,先不存(換碼成功才用 `save` 取代舊的)。
    func generate() throws -> DPoPKey

    /// 用這把金鑰取代存著的。
    func save(_ key: DPoPKey) throws

    func delete()
}
