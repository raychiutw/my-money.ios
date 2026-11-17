import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 受保護的 session 失效(臉部資料變更)時,連同 DPoP 金鑰一起刪掉(#364 第 5 點、ADR-0012 刪除時機)。
@Suite("受保護的 session 失效")
struct InvalidatedProtectedSessionTests {
    @Test("讀取時保存已失效:刪掉 DPoP 金鑰")
    func invalidatedDeletesDPoPKey() async {
        let keys = InMemoryDPoPKeyStore()
        let storage = KeychainSessionStorage(service: "com.raychiu.mymoney.tests.\(UUID().uuidString)", dpopKeys: keys)

        let loaded = await storage.loadProtected(reason: "測試")

        #expect(loaded == .invalidated)
        #expect(keys.load() == nil)
    }
}
