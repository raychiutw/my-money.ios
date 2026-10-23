import SwiftUI

/// 金額欄(DESIGN.md「明細卡與輸入框」輸入框方案 B，#281、#284):沒有外置標籤，空的時候用提示文字(欄位名稱)當標籤;
/// 大字、前面有「$」，文字從前緣(左邊)開始輸入;填了內容之後提示文字會消失，所以欄位上方浮出小字的欄位名稱(同一張表單
/// 有好幾個金額欄時才分得出是哪一欄，VoiceOver 另外念欄位名稱)。數字鍵盤、等寬數字，取得焦點時選取全部文字(#32)。
///
/// 取得焦點時全選，直接輸入就會取代原值(880 改成 990，不會變成 990880)。focus 沿用呼叫端的 `FocusState`(Bool 或 enum 都可以),
/// 呼叫端照舊用它收起鍵盤或一開始就讓金額欄取得焦點。
struct AmountField<Value: Hashable>: View {
    private let title: String
    /// 綁定的文字永遠是純數字(model 與驗證都不知道千分位);欄位顯示的是 `display`(#256)。
    @Binding private var text: String
    private let focus: FocusState<Value>.Binding
    private let focusValue: Value
    private let identifier: String
    @State private var selection: TextSelection?
    @State private var display: String

    init(
        _ title: String, text: Binding<String>,
        focus: FocusState<Value>.Binding, equals focusValue: Value, identifier: String
    ) {
        self.title = title
        _text = text
        self.focus = focus
        self.focusValue = focusValue
        self.identifier = identifier
        _display = State(initialValue: Self.shown(text.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !display.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "$")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(title, text: $display, selection: $selection, prompt: Text(title))
                    .multilineTextAlignment(.leading)
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
            .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 純數字 → 顯示的文字;帶進來的不是純數字(不該發生)就原樣顯示，讓驗證擋下。
    private static func shown(_ text: String) -> String {
        AmountDigits.isPlain(text) ? AmountDigits.grouped(text) : text
    }

    /// 使用者打字、刪除或貼上之後:取出純數字寫回綁定，重新格式化顯示，游標留在同樣數量的數字後面。
    /// 含不合法字元或超過位數上限的輸入整次拒絕，欄位退回上一個值。
    private func userEdited(_ edited: String) {
        guard let digits = AmountDigits.digits(from: edited) else {
            // 綁定的文字本來就不是純數字(帶入了有小數點的舊金額):照使用者打的存回去，不凍住欄位;驗證在送出時擋下。
            if !AmountDigits.isPlain(text) {
                if edited != text { text = edited }
                return
            }
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
