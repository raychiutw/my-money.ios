import Foundation
import MyMoneyFeatures
import Testing

/// 金額欄的千分位(#256):欄位顯示有千分位,綁定的文字永遠是純數字。轉換是純函式,邊界情況在這裡驗。
@Suite("金額欄的千分位(AmountDigits)")
struct AmountFormattingTests {
    @Test("純數字加千分位:每三位一個逗號，固定用逗號不跟語系", arguments: [
        ("", ""), ("0", "0"), ("7", "7"), ("999", "999"), ("1000", "1,000"), ("1234", "1,234"),
        ("12345", "12,345"), ("123456", "123,456"), ("1234567", "1,234,567"), ("999999999999", "999,999,999,999"),
    ])
    func grouping(digits: String, expected: String) {
        #expect(AmountDigits.grouped(digits) == expected)
    }

    @Test("輸入轉純數字:去掉逗號與前後空白;已有千分位的文字(貼上)不是錯誤", arguments: [
        ("1234567", "1234567"), ("1,234,567", "1234567"), (" 1,234 ", "1234"), ("1,23", "123"), ("", ""),
    ])
    func normalizingAcceptedInput(input: String, expected: String) {
        #expect(AmountDigits.digits(from: input) == expected)
    }

    @Test("前導 0 去掉，但單獨的 0 保留(送出時才由「金額必須大於 0」擋下)", arguments: [
        ("007", "7"), ("0", "0"), ("00", "0"), ("0,000", "0"), ("0100", "100"),
    ])
    func leadingZeros(input: String, expected: String) {
        #expect(AmountDigits.digits(from: input) == expected)
    }

    @Test("含其他字元整次拒絕(回傳 nil):小數點、負號、英文字、全形數字、貨幣符號——不過濾成別的數字", arguments: [
        "12.5", "-100", "12abc", "１２３", "$1,000", "1e3", "1 000",
    ])
    func rejectsOtherCharacters(input: String) {
        #expect(AmountDigits.digits(from: input) == nil)
    }

    @Test("位數上限 12 位:剛好 12 位接受，13 位拒絕")
    func digitLimit() {
        #expect(AmountDigits.digits(from: "999999999999") == "999999999999")
        #expect(AmountDigits.digits(from: "1000000000000") == nil)
        #expect(AmountDigits.digits(from: "0000000000001") == "1", "前導 0 不算位數")
    }

    @Test("游標:以「游標左邊有幾個數字」為準，重新格式化後放在同樣數量數字的右邊")
    func caretFollowsDigits() {
        // 顯示「1,234」,游標在「2」後面(左邊 2 個數字)——插入一個數字後變成 5 位「12,345」,游標在原來數字後面。
        #expect(AmountDigits.digitCount(in: "1,234", before: 3) == 2)
        #expect(AmountDigits.digitCount(in: "1,234", before: 0) == 0)
        #expect(AmountDigits.digitCount(in: "1,234", before: 5) == 4)
        #expect(AmountDigits.offset(in: "12,345", afterDigits: 3) == 4, "「12,3」後面")
        #expect(AmountDigits.offset(in: "12,345", afterDigits: 2) == 2, "逗號前面")
        #expect(AmountDigits.offset(in: "12,345", afterDigits: 0) == 0)
        #expect(AmountDigits.offset(in: "12,345", afterDigits: 5) == 6)
        #expect(AmountDigits.offset(in: "", afterDigits: 0) == 0)
    }

    @Test("全是數字(含空字串)才套千分位規則;帶入有小數點的舊金額時欄位照常編輯", arguments: [
        ("", true), ("1234", true), ("12.5", false), ("1,234", false), ("-5", false),
    ])
    func plainText(text: String, expected: Bool) {
        #expect(AmountDigits.isPlain(text) == expected)
    }
}
