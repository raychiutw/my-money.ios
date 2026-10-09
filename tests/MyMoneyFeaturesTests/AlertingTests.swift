import Foundation
import MyMoneyFeatures
import Testing

/// 列表上的變更(#211 第 2 項):成功才遞增資料版本、失敗只出 alert，順序與條件只在一處。
@MainActor
@Suite("列表變更與失敗提示(Alerting)")
struct AlertingTests {
    @MainActor
    final class List: Alerting {
        var alertMessage: String?
    }

    struct Boom: LocalizedError { var errorDescription: String? { "壞了" } }

    @Test("成功:回傳結果、資料版本遞增一次、沒有 alert")
    func success() async {
        let list = List()
        let dataVersion = DataVersion()
        let before = dataVersion.value
        let result = await list.commit(dataVersion) { "好了" }
        #expect(result == "好了")
        #expect(dataVersion.value == before + 1)
        #expect(list.alertMessage == nil)
    }

    @Test("失敗:回傳 nil、alert 帶錯誤訊息、資料版本不變")
    func failure() async {
        let list = List()
        let dataVersion = DataVersion()
        let before = dataVersion.value
        let result: Int? = await list.commit(dataVersion) { throw Boom() }
        #expect(result == nil)
        #expect(list.alertMessage == "壞了")
        #expect(dataVersion.value == before)
    }
}
