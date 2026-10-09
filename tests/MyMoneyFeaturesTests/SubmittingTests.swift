import Foundation
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 表單送出(#210 第 2 項):送出中旗標與失敗訊息的規則只在一處。
@MainActor
@Suite("表單送出(Submitting)")
struct SubmittingTests {
    @MainActor
    final class Form: Submitting {
        var isSaving = false
        var errorMessage: String?
    }

    struct Boom: LocalizedError { var errorDescription: String? { "壞了" } }
    struct Silent: LocalizedError { var errorDescription: String? { "" } }

    @Test("成功:回傳結果、送出中旗標復原、不留錯誤訊息")
    func success() async {
        let form = Form()
        let result = await form.submitting(failure: "儲存失敗") { 42 }
        #expect(result == 42)
        #expect(!form.isSaving)
        #expect(form.errorMessage == nil)
    }

    @Test("失敗:回傳 nil、訊息取自錯誤、旗標復原")
    func failure() async {
        let form = Form()
        let result: Int? = await form.submitting(failure: "儲存失敗") { throw Boom() }
        #expect(result == nil)
        #expect(form.errorMessage == "壞了")
        #expect(!form.isSaving)
    }

    @Test("錯誤沒有訊息時用呼叫端給的備用文字")
    func fallbackMessage() async {
        let form = Form()
        let _: Int? = await form.submitting(failure: "儲存失敗") { throw Silent() }
        #expect(form.errorMessage == "儲存失敗")
    }

    @Test("送出期間旗標為 true")
    func savingWhileRunning() async {
        let form = Form()
        let gate = Gate()
        let task = Task { await form.submitting(failure: "儲存失敗") { await gate.pass() } }
        await gate.waitUntilReached()
        #expect(form.isSaving)
        await gate.open()
        _ = await task.value
        #expect(!form.isSaving)
    }
}
