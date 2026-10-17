import Foundation

/// 金額欄的千分位(#256):欄位顯示有千分位，綁定的文字永遠是純數字。轉換是純函式，欄位元件(`AmountField`)只負責接線。
package enum AmountDigits {
    /// 位數上限(`999,999,999,999`)。
    package static let maxDigits = 12

    /// 欄位裡的文字 → 純數字。去掉逗號與前後空白、去前導 0(單獨的 0 保留，送出時才由「金額必須大於 0」擋下)。
    /// 含其他字元(小數點、負號、英文字、全形數字、貨幣符號)或超過位數上限回 `nil`——整次輸入拒絕，欄位維持原值,
    /// 不過濾成別的數字(貼上 `12.5` 不能默默變成 `125`)。
    package static func digits(from input: String) -> String? {
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard stripped.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        let significant = stripped.drop { $0 == "0" }
        // 全是 0(或只有 0):保留一個 0;空字串維持空字串。
        let digits = significant.isEmpty ? (stripped.isEmpty ? "" : "0") : String(significant)
        return digits.count <= maxDigits ? digits : nil
    }

    /// 純數字 → 欄位顯示的文字:每三位一個逗號，固定用逗號，不跟裝置語系走。
    package static func grouped(_ digits: String) -> String {
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return String(result.reversed())
    }

    /// `text` 裡 `offset`(字元位置)左邊有幾個數字。
    package static func digitCount(in text: String, before offset: Int) -> Int {
        text.prefix(max(offset, 0)).filter { ("0"..."9").contains($0) }.count
    }

    /// 重新格式化後,`text` 裡「左邊剛好有 `count` 個數字」的字元位置——游標以此為準，不受逗號增減影響。
    package static func offset(in text: String, afterDigits count: Int) -> Int {
        guard count > 0 else { return 0 }
        var seen = 0
        for (index, character) in text.enumerated() where ("0"..."9").contains(character) {
            seen += 1
            if seen == count { return index + 1 }
        }
        return text.count
    }
}
