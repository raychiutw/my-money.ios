import SwiftUI

/// 金額欄：靠右對齊、數字鍵盤、等寬數字，取得焦點時選取全部文字(#32)。
///
/// 靠右對齊的 `TextField` 第一次點下去，游標一律停在原本的數字前面，880 改成 990 會變成 990880。
/// 取得焦點時全選，直接輸入就會取代原值。focus 沿用呼叫端的 `FocusState`(Bool 或 enum 都可以),
/// 呼叫端照舊用它收起鍵盤或一開始就讓金額欄取得焦點。
struct AmountField<Value: Hashable>: View {
    private let title: String
    /// 綁定的文字永遠是純數字(model 與驗證都不知道千分位);欄位顯示的是 `display`(#256)。
    @Binding private var text: String
    private let prompt: Text?
    private let focus: FocusState<Value>.Binding
    private let focusValue: Value
    private let identifier: String
    @State private var selection: TextSelection?
    @State private var display: String

    init(
        _ title: String, text: Binding<String>, prompt: Text? = nil,
        focus: FocusState<Value>.Binding, equals focusValue: Value, identifier: String
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.focus = focus
        self.focusValue = focusValue
        self.identifier = identifier
        _display = State(initialValue: Self.shown(text.wrappedValue))
    }

    var body: some View {
        TextField(title, text: $display, selection: $selection, prompt: prompt)
            .multilineTextAlignment(.trailing)
            .numberKeyboard()
            .monospacedDigit()
            .focused(focus, equals: focusValue)
            .accessibilityIdentifier(identifier)
            .onChange(of: display) { _, newValue in userEdited(newValue) }
            // model 端改了文字(帶入預設金額、送出後清空):顯示跟著換。
            .onChange(of: text) { _, newValue in
                if AmountDigits.digits(from: display) != newValue { display = Self.shown(newValue) }
            }
            .onChange(of: focus.wrappedValue == focusValue) { _, isFocused in
                guard isFocused else { return }
                selection = TextSelection(range: display.startIndex..<display.endIndex)
            }
    }

    /// 純數字 → 顯示的文字;帶進來的不是純數字(不該發生)就原樣顯示，讓驗證擋下。
    private static func shown(_ text: String) -> String {
        text.allSatisfy { ("0"..."9").contains($0) } ? AmountDigits.grouped(text) : text
    }

    /// 使用者打字、刪除或貼上之後:取出純數字寫回綁定，重新格式化顯示，游標留在同樣數量的數字後面。
    /// 含不合法字元或超過位數上限的輸入整次拒絕，欄位退回上一個值。
    private func userEdited(_ edited: String) {
        guard let digits = AmountDigits.digits(from: edited) else {
            display = Self.shown(text)
            return
        }
        if digits != text { text = digits }
        let formatted = AmountDigits.grouped(digits)
        guard formatted != edited else { return }
        let caretDigits = caretOffset(in: edited).map { AmountDigits.digitCount(in: edited, before: $0) }
        display = formatted
        if let caretDigits {
            let offset = AmountDigits.offset(in: formatted, afterDigits: caretDigits)
            selection = TextSelection(insertionPoint: formatted.index(formatted.startIndex, offsetBy: offset))
        }
    }

    /// 目前游標(沒有選取範圍時)在 `edited` 裡的字元位置。
    private func caretOffset(in edited: String) -> Int? {
        guard case .selection(let range)? = selection?.indices, range.isEmpty else { return nil }
        guard range.upperBound <= edited.endIndex else { return nil }
        return edited.distance(from: edited.startIndex, to: range.upperBound)
    }
}
