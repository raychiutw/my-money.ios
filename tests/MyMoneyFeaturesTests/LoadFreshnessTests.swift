import Foundation
import MyMoneyFeatures
import Testing

/// 載入生命週期(#210 第 1 項):載入階段與「資料版本、檢視範圍變了才重載」的判斷只在一處。
@Suite("載入生命週期(LoadPhase、LoadFreshness)")
struct LoadFreshnessTests {
    @Test("還沒載入過:一律過期")
    func neverLoaded() {
        let freshness = LoadFreshness<String>()
        #expect(freshness.isStale(version: 0, scope: "all"))
        #expect(freshness.version == nil)
        #expect(freshness.scope == nil)
    }

    @Test("載入後版本與範圍都沒變:不過期")
    func unchanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(version: 3, scope: "all")
        #expect(!freshness.isStale(version: 3, scope: "all"))
        #expect(freshness.version == 3)
        #expect(freshness.scope == "all")
    }

    @Test("資料版本變了:過期")
    func versionChanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(version: 3, scope: "all")
        #expect(freshness.isStale(version: 4, scope: "all"))
    }

    @Test("檢視範圍變了:過期")
    func scopeChanged() {
        var freshness = LoadFreshness<String>()
        freshness.markLoaded(version: 3, scope: "all")
        #expect(freshness.isStale(version: 3, scope: "household"))
    }

    @Test("沒有檢視範圍的畫面只看資料版本")
    func unscoped() {
        var freshness = LoadFreshness<Unscoped>()
        #expect(freshness.isStale(version: 1))
        freshness.markLoaded(version: 1)
        #expect(!freshness.isStale(version: 1))
        #expect(freshness.isStale(version: 2))
    }

    @Test("載入失敗的階段帶錯誤訊息")
    func failedPhase() {
        struct Boom: LocalizedError { var errorDescription: String? { "壞了" } }
        #expect(LoadPhase.failure(Boom()) == .failed("壞了"))
    }
}
