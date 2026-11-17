import CryptoKit
import MyMoneyAPI
import Synchronization

/// 測試用的 DPoP 金鑰存放:軟體 P-256 金鑰放在記憶體;記下目前的公鑰,讓測試驗 proof 的簽章。
final class InMemoryDPoPKeyStore: DPoPKeyStore {
    private let key: Mutex<DPoPKey?>

    init(hasKey: Bool = true) {
        key = Mutex(hasKey ? DPoPKey(P256.Signing.PrivateKey()) : nil)
    }

    /// 目前存著的公鑰;刪掉之後是 `nil`。
    var publicKey: P256.Signing.PublicKey? {
        key.withLock { $0?.publicKey }
    }

    func load() -> DPoPKey? {
        key.withLock { $0 }
    }

    func generate() throws -> DPoPKey {
        DPoPKey(P256.Signing.PrivateKey())
    }

    func save(_ new: DPoPKey) throws {
        key.withLock { $0 = new }
    }

    func delete() {
        key.withLock { $0 = nil }
    }
}
