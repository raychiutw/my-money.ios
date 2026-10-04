import SwiftUI

/// 表單裡的備註欄(#170)——記一筆與編輯、ATM 提款／轉帳、信用卡還款、報銷共用。
///
/// 一般字級是單行 `TextField`。大字級下單行放不下,沒在編輯時值會被截成「家庭基金撥…」(報銷與信用卡還款的預設備註很長),
/// HIG 的 Typography 說大字級盡量不截斷,所以**無障礙字級**改成可以長高的多行欄位(`axis: .vertical`)。
/// 備註還是單行語意:Return 不換行,而是收起鍵盤(跟單行欄位一樣);貼上含換行的文字會把換行拿掉。
struct NoteField<Value: Hashable>: View {
    @Binding var text: String
    let prompt: String
    let focus: FocusState<Value?>.Binding
    let value: Value

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        field
            .focused(focus, equals: value)
    }

    @ViewBuilder
    private var field: some View {
        if dynamicTypeSize.isAccessibilitySize {
            TextField("備註", text: $text, prompt: Text(prompt), axis: .vertical)
                .lineLimit(1...10)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    focus.wrappedValue = nil
                }
        } else {
            TextField("備註", text: $text, prompt: Text(prompt))
        }
    }
}
