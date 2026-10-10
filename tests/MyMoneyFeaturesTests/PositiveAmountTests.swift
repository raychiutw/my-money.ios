import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import Testing

/// 正整數金額的檢查(#235):解析規則與統一句型的錯誤文案只在一處。
@MainActor
@Suite("正整數金額(PositiveAmount)")
struct PositiveAmountTests {
    @MainActor
    final class Form: Submitting {
        var isSaving = false
        var errorMessage: String?
    }

    @Test("只接受大於 0 的整數;前後空白不算", arguments: [("12", 12), (" 12 ", 12), ("007", 7), ("1", 1), ("100000", 100_000)])
    func accepts(text: String, expected: Int) {
        #expect(PositiveAmount.parse(text) == Money(Decimal(expected)))
    }

    @Test("空字串、0、非數字、負號、千分位、小數都不接受", arguments: ["", " ", "0", "00", "abc", "-5", "1,000", "12.5", "12abc", "１２"])
    func rejects(text: String) {
        #expect(PositiveAmount.parse(text) == nil)
    }

    @Test("錯誤文案的句型固定為「請輸入有效的{欄位名}」")
    func message() {
        #expect(PositiveAmount.invalidMessage(label: "金額") == "請輸入有效的金額")
        #expect(PositiveAmount.invalidMessage(label: "每期金額") == "請輸入有效的每期金額")
    }

    @Test("表單 model:有效時回傳金額、不動錯誤訊息")
    func formAccepts() {
        let form = Form()
        #expect(form.positiveAmount("250", label: "金額") == Money(250))
        #expect(form.errorMessage == nil)
    }

    @Test("表單 model:無效時回傳 nil，並把統一句型的訊息放進 errorMessage")
    func formRejects() {
        let form = Form()
        #expect(form.positiveAmount("abc", label: "繳款金額") == nil)
        #expect(form.errorMessage == "請輸入有效的繳款金額")
    }
}
