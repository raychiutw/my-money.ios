import CryptoKit
import MyMoneyAPI
import Synchronization

/// 測試用的 DPoP 金鑰存放:軟體 P-256 金鑰放在記憶體;記下目前的公鑰,讓測試驗 proof 的簽章。
final class InMemoryDPoPKeyStore: DPoPKeyStore {
    private let key: Mutex<P256.Signing.PrivateKey?>

    init(hasKey: Bool = true) {
        key = Mutex(hasKey ? P256.Signing.PrivateKey() : nil)
    }

    /// 目前的公鑰;刪掉之後是 `nil`。
    var publicKey: P256.Signing.PublicKey? {
        key.withLock { $0?.publicKey }
    }

    func load() -> DPoPKey? {
        key.withLock { $0.map(DPoPKey.init) }
    }

    func create() throws -> DPoPKey {
        let new = P256.Signing.PrivateKey()
        key.withLock { $0 = new }
        return DPoPKey(new)
    }

    func delete() {
        key.withLock { $0 = nil }
    }
}
