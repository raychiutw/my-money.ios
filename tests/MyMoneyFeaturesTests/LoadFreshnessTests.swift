import Foundation
import MyMoneyFeatures
import Testing

/// 載入生命週期(#210 第 1 項):載入階段與「資料版本、檢視範圍變了才重載」的判斷只在一處。
@Suite("載入生命週期(LoadPhase、LoadFreshness)")
struct LoadFreshnessTests {
    @Test("還沒載入過:一律過期")
    func neverLoaded() {
        let freshness = LoadFreshness<String>()
        #expect(freshness.isStale(ReloadKey(scope: "all", version: 0)))
        #expect(freshness.version == nil)
        #expect(freshness.scope == nil)
    }

    @Test("載入後版本與範圍都沒變:不過期")
    func unchanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(ReloadKey(scope: "all", version: 3))
        #expect(!freshness.isStale(ReloadKey(scope: "all", version: 3)))
        #expect(freshness.version == 3)
        #expect(freshness.scope == "all")
    }

    @Test("資料版本變了:過期")
    func versionChanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(ReloadKey(scope: "all", version: 3))
        #expect(freshness.isStale(ReloadKey(scope: "all", version: 4)))
    }

    @Test("檢視範圍變了:過期")
    func scopeChanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(ReloadKey(scope: "all", version: 3))
        #expect(freshness.isStale(ReloadKey(scope: "household", version: 3)))
    }

    @Test("沒有檢視範圍的畫面只看資料版本")
    func unscoped() {
        var freshness = LoadFreshness<Unscoped>()
        #expect(freshness.isStale(ReloadKey(version: 1)))
        freshness.markLoaded(ReloadKey(version: 1))
        #expect(!freshness.isStale(ReloadKey(version: 1)))
        #expect(freshness.isStale(ReloadKey(version: 2)))
    }

    @Test("載入失敗的階段帶錯誤訊息")
    func failedPhase() {
        struct Boom: LocalizedError { var errorDescription: String? { "壞了" } }
        #expect(LoadPhase.failure(Boom()) == .failed("壞了"))
    }
}
