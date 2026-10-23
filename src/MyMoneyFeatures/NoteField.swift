import SwiftUI

/// 表單裡的備註欄(#170)——記一筆與編輯、ATM 提款／轉帳、信用卡還款、報銷共用。輸入框方案 B(DESIGN.md「明細卡與輸入框」,#281、#284):
/// 沒有外置標籤，空的時候用提示文字「備註」當標籤、文字從前緣輸入;填了內容之後欄位上方浮出小字「備註」，不靠提示文字辨認。
///
/// 一般字級是單行 `TextField`。大字級下單行放不下,沒在編輯時值會被截成「家庭基金撥…」(報銷與信用卡還款的預設備註很長),
/// HIG 的 Typography 說大字級盡量不截斷,所以**無障礙字級**改成可以長高的多行欄位(`axis: .vertical`)。
/// 備註還是單行語意:Return 不換行,而是收起鍵盤(跟單行欄位一樣);貼上含換行的文字會把換行拿掉。
struct NoteField<Value: Hashable>: View {
    @Binding var text: String
    let focus: FocusState<Value?>.Binding
    let value: Value

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !text.isEmpty {
                Text("備註")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            field
                .focused(focus, equals: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var field: some View {
        if dynamicTypeSize.isAccessibilitySize {
            TextField("備註", text: $text, prompt: Text("備註"), axis: .vertical)
                .lineLimit(1...10)
                .onChange(of: text) { _, newValue in
                    guard newValue.contains("\n") else { return }
                    text = newValue.replacingOccurrences(of: "\n", with: "")
                    focus.wrappedValue = nil
                }
        } else {
            TextField("備註", text: $text, prompt: Text("備註"))
        }
    }
}
