import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension EnvironmentValues {
    /// 新密碼欄位是否讓密碼管理工具建議高強度密碼(`textContentType(.newPassword)`,預設開啟)。
    ///
    /// 只有 `-uiTesting` 的 composition root 會關掉。CI 的錄影顯示：點密碼欄位後出現的是系統的
    /// 「Use Strong Password?」sheet,鍵盤不會出現，`typeText` 只送得進 1 個字元。
    /// 只拿掉 `.newPassword` 不夠，因為系統還會用 heuristics 認出註冊表單;關掉時改標成
    /// `.oneTimeCode`,讓系統不把它當成密碼欄位。
    @Entry public var suggestsStrongPasswords = true
}

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

/// 複製到系統剪貼簿。
@MainActor
func copyToPasteboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}
