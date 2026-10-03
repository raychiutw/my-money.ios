import SwiftUI

extension View {
    /// 整列都點得到:`LabeledContent` 在大字級會把標籤放在欄位上方,點標籤(整列的上半)也要能開始輸入,
    /// 不然點整列的正中央會落在標籤上,欄位沒有焦點(#157)。
    func tapToFocus<Value: Hashable>(_ focus: FocusState<Value?>.Binding, equals value: Value) -> some View {
        contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = value }
    }
}
