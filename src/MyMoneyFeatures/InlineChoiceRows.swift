import SwiftUI

/// 內嵌選擇列(ADR-0004、#90、#91):2～5 個選項各一列，點一下就選，選取的那列右邊是**品牌粉紅的勾勾**(ADR-0008)。
///
/// 系統的 `Picker(.inline)` 勾勾畫成主要文字色，`.tint` 也染不到(實測，#147),所以自己畫:一列一個 `Button`,
/// 字是 body 字級、主要文字色，選取的列加上 `isSelected`，VoiceOver 念「已選取」。放在 `Form`／`List` 的 `Section` 裡用。
struct InlineChoiceRows<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value

    init(_ options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options.map { Option(value: $0.value, title: $0.title) }
        _selection = selection
    }

    var body: some View {
        ForEach(options) { option in
            let isSelected = option.value == selection
            Button {
                selection = option.value
            } label: {
                HStack {
                    Text(option.title)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.brandPink)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
