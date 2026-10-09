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
    /// `.oneTimeCode`,讓系統不把它當成密碼欄位。登入頁的密碼欄同理:用 Return 登入後，系統偶爾彈出
    /// 「要儲存密碼嗎？」蓋住畫面，UI 測試的截圖和查詢都會落空。
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
        modifier(KeyboardDismissal(focus: focus))
        #else
        self
        #endif
    }

    /// tab 首頁不顯示標題與副標題(#108):tab bar 已經說明目前在哪個 tab,標題是重複的資訊，還佔空間。
    /// 標題文字仍設給系統(返回鍵與 VoiceOver 的脈絡用)，只是不顯示。
    func tabRootNavigation(_ name: String) -> some View {
        #if os(iOS)
        navigationTitle(name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            // 頂端遮罩(#205):隱藏標題後導覽列只剩工具列按鈕,系統的捲動邊緣效果卻仍從狀態列蓋到工具列底下一大塊。
            // 關掉它,只在狀態列(靈動島)那一條放遮罩;工具列那一排只有按鈕自己的玻璃。
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) { StatusBarMask() }
        #else
        navigationTitle(name)
        #endif
    }

    /// 滾輪式選擇(年、月)。只有 iOS 有 `.wheel`。
    func wheelPickerStyle() -> some View {
        #if os(iOS)
        pickerStyle(.wheel)
        #else
        self
        #endif
    }

    /// 區塊之間的間距縮小(總覽的數字磚、提示)。只有 iOS 有 `listSectionSpacing`。
    func compactSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
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

extension Picker {
    /// 列上顯示目前的值，點了推入清單頁(選項多或不固定的選擇，ADR-0004)。`.navigationLink` 樣式 macOS 沒有;
    /// 為了讓 package 在 macOS 上也能編譯測試，macOS 維持預設樣式。
    func navigationLinkStyle() -> some View {
        #if os(iOS)
        pickerStyle(.navigationLink)
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

#if os(iOS)
/// `keyboardDismissal` 的實作:「完成」鈕在 iOS 26 是浮在鍵盤上方的玻璃圓鈕,系統把焦點欄位捲到鍵盤上緣就停,
/// 欄位的下半部被這顆鈕(或整個欄位被鍵盤)蓋住。有焦點(鍵盤出現)時,在底部多留一段鈕的高度,捲動才會把欄位捲到鈕的上面。
private struct KeyboardDismissal<Field: Hashable>: ViewModifier {
    let focus: FocusState<Field?>.Binding
    /// 「完成」鈕的高度加上它與欄位之間的空隙;跟著字級放大。
    @ScaledMetric(relativeTo: .body) private var doneHeight = 88

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus.wrappedValue = nil }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: focus.wrappedValue == nil ? 0 : doneHeight)
            }
    }
}
#endif

#if os(iOS)
/// 只蓋狀態列(靈動島)那一條的遮罩(#205):高度是視窗的頂端安全區(有、沒有動態島的機型自動不同),
/// 系統材質加底部淡出,捲過去的內容不會跟時間、訊號、電量混在一起。
private struct StatusBarMask: View {
    var body: some View {
        Rectangle()
            .fill(.bar)
            .frame(height: Self.statusBarHeight)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 視窗的頂端安全區高度(狀態列);取不到時用 0(沒有遮罩,不會壞)。
    private static var statusBarHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top ?? scene?.statusBarManager?.statusBarFrame.height ?? 0
    }
}
#endif

/// 表單裡錯誤訊息那一列的捲動目標(#208 之外的修正:記一筆沒選帳戶的錯誤在表單最上面,鍵盤開著、表單捲下去時看不到)。
enum FormError {
    static let id = "formError"
}

extension View {
    /// 錯誤訊息出現時:收起鍵盤並捲到訊息那一列(它要有 `.id(FormError.id)`),使用者才看得到哪裡錯了。
    func revealsError<Field: Hashable>(_ message: String?, clearing focus: FocusState<Field?>.Binding) -> some View {
        ScrollViewReader { proxy in
            onChange(of: message) { _, message in
                guard message != nil else { return }
                focus.wrappedValue = nil
                withAnimation { proxy.scrollTo(FormError.id, anchor: .top) }
            }
        }
    }
}

extension View {
    /// 操作失敗的提示(#211 第 2 項):`message` 有值就跳出 alert,按「好」後呼叫 `dismiss` 清掉。
    /// 列表上的刪除、出帳等變更失敗時,model 的 `alertMessage` 就是這裡的 `message`。
    func errorAlert(_ title: String, message: String?, dismiss: @escaping () -> Void) -> some View {
        alert(title, isPresented: Binding(get: { message != nil }, set: { if !$0 { dismiss() } })) {
            Button("好") {}
        } message: {
            Text(message ?? "")
        }
    }
}
