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

    /// 按下「複製」後，按鈕顯示「已複製」多久才改回來。預設 2 秒，跟 web 的 `setTimeout(..., 2000)` 一樣。
    ///
    /// 只有 `-uiTesting` 的 composition root 會拉長。CI 的 runner 從點擊到第一次查詢要 2 秒以上，
    /// 查到的時候已經改回「複製」了(run 36371483722:點擊在 44.80s,第一次查詢在 47.22s)。
    @Entry public var copiedFeedbackDuration: Duration = .seconds(2)
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

    /// 金額欄位的鍵盤：數字鍵盤。number pad 沒有 Return 鍵，所以要搭配 `keyboardDismissal`。
    func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// 表單收起鍵盤的方式(#61):鍵盤上方的「完成」鈕清掉整個表單的焦點，不管焦點在哪個欄位都收起鍵盤;
    /// 捲動表單也會收起鍵盤。
    ///
    /// 表單的所有文字欄位(包括備註)都要綁到同一個 `focus`。沒綁到的欄位取得焦點時，`focus` 早就是 `nil`,
    /// 按「完成」不會有反應。number pad 沒有 Return 鍵，所以有金額欄的表單一定要加。
    ///
    /// 捲動用 `.immediately`,一開始捲動就收起。`.interactively` 要手指往下拖進鍵盤才會收起，
    /// 但表單大多在 sheet 裡，在最上面往下拖拉動的是 sheet 本身。
    func keyboardDismissal<Field: Hashable>(clearing focus: FocusState<Field?>.Binding) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focus.wrappedValue = nil }
            }
        }
        .scrollDismissesKeyboard(.immediately)
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
