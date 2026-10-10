import Foundation
import MyMoneyDomain

/// 使用者輸入的「大於 0 的整數金額」(#235):解析規則與統一句型的錯誤文案只在這裡。
/// 各表單自己的額外規則(轉出與轉入不可相同、繳款不可超過待繳額…)仍留在各自的 model。
package enum PositiveAmount {
    /// 前後空白不算;有任何不是 0 到 9 的字元(千分位、小數點、負號)、或結果不大於 0 都是 `nil`。
    package static func parse(_ text: String) -> Money? {
        Money(wholeNumber: text).flatMap { $0 > .zero ? $0 : nil }
    }

    /// 例如「請輸入有效的金額」「請輸入有效的每期金額」:欄位名用畫面上的標籤(#218)。
    package static func invalidMessage(label: String) -> String {
        "請輸入有效的\(label)"
    }
}

extension Submitting {
    /// 解析金額欄;無效時把統一句型的訊息放進 `errorMessage` 並回傳 `nil`。
    package func positiveAmount(_ text: String, label: String) -> Money? {
        guard let amount = PositiveAmount.parse(text) else {
            errorMessage = PositiveAmount.invalidMessage(label: label)
            return nil
        }
        return amount
    }
}
