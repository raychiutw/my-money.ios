import CryptoKit
import Foundation
import Security

/// DPoP 金鑰存在 Keychain(#337)。實機的私鑰在 Secure Enclave,Keychain 只存它加密過的參照(`dataRepresentation`),
/// 換到別台裝置也用不了;模擬器沒有 Secure Enclave,改存軟體金鑰。
///
/// 存取等級跟登入工作階段相同:`WhenUnlockedThisDeviceOnly`(見 `KeychainSessionStorage`)。
public struct KeychainDPoPKeyStore: DPoPKeyStore {
    private static let account = "dpop"
    private let service: String
    private let secureEnclave: Bool

    /// - Parameter secureEnclave: 用不用 Secure Enclave;預設看這台有沒有(模擬器沒有)。
    public init(service: String, secureEnclave: Bool = SecureEnclave.isAvailable) {
        self.service = service
        self.secureEnclave = secureEnclave
    }

    public func load() -> DPoPKey? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        if secureEnclave {
            return (try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)).map(DPoPKey.init)
        }
        return (try? P256.Signing.PrivateKey(rawRepresentation: data)).map(DPoPKey.init)
    }

    public func generate() throws -> DPoPKey {
        secureEnclave ? DPoPKey(try SecureEnclave.P256.Signing.PrivateKey()) : DPoPKey(P256.Signing.PrivateKey())
    }

    public func save(_ key: DPoPKey) throws {
        delete()
        var item = itemQuery
        item[kSecValueData as String] = key.storedRepresentation
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public func delete() {
        SecItemDelete(itemQuery as CFDictionary)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
