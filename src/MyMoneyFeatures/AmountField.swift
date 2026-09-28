import SwiftUI

/// 金額欄：靠右對齊、數字鍵盤、等寬數字，取得焦點時選取全部文字(#32)。
///
/// 靠右對齊的 `TextField` 第一次點下去，游標一律停在原本的數字前面，880 改成 990 會變成 990880。
/// 取得焦點時全選，直接輸入就會取代原值。focus 沿用呼叫端的 `FocusState`(Bool 或 enum 都可以),
/// 呼叫端照舊用它收起鍵盤或一開始就讓金額欄取得焦點。
struct AmountField<Value: Hashable>: View {
    private let title: String
    @Binding private var text: String
    private let prompt: Text?
    private let focus: FocusState<Value>.Binding
    private let focusValue: Value
    private let identifier: String
    @State private var selection: TextSelection?

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
    }

    var body: some View {
        TextField(title, text: $text, selection: $selection, prompt: prompt)
            .multilineTextAlignment(.trailing)
            .numberKeyboard()
            .monospacedDigit()
            .focused(focus, equals: focusValue)
            .accessibilityIdentifier(identifier)
            .onChange(of: focus.wrappedValue == focusValue) { _, isFocused in
                guard isFocused else { return }
                selection = TextSelection(range: text.startIndex..<text.endIndex)
            }
    }
}
