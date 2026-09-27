import SwiftUI

/// 只有 iOS 才有的 modifier。`swift test` 會在 macOS 上編譯 Features,所以集中在這裡用 `#if os(iOS)` 包起來。
extension View {
    /// Email 欄位的鍵盤:email 鍵盤、不自動大寫。
    func emailKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// 金額欄位的鍵盤：數字鍵盤。number pad 沒有 Return 鍵，所以要搭配 `keyboardDoneButton`。
    func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// 鍵盤上方的「完成」鈕，用來收起數字鍵盤。
    func keyboardDoneButton(action: @escaping () -> Void) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成", action: action)
            }
        }
        #else
        self
        #endif
    }

    /// 標題以小字顯示在導覽列(push 進來的頁面)。
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        toolbarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
