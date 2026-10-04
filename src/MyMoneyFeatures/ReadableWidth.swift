import SwiftUI

/// iPad 上內容限制在可讀寬度並置中(#173、HIG Layout:內容不要隨視窗拉伸)。
///
/// 清單的列左邊是名稱、右邊是金額,在 iPad 直向(820pt)會隔七百多 pt,眼睛要跨整個畫面才對得上;登入的欄位和按鈕也有 800pt 寬。
/// 用 `contentMargins(.horizontal, …, for: .scrollContent)` 把捲動內容左右各推進去:背景與捲動範圍仍撐滿整個視窗,
/// 捲動條也還在視窗邊緣;視窗比 `maxWidth` 窄(iPhone、Split View)時邊界是 0,版面不變。
/// 掛在 tab 的內容或登入頁上,往下的捲動容器(含推入的頁面)都套用;sheet 是另一個呈現,不受影響(它們本來就是窄的)。
public struct ReadableWidth: ViewModifier {
    /// 內容最大寬度(pt):約 700,跟系統的可讀內容寬度同一個量級。
    public static let maxWidth: CGFloat = 700

    @State private var availableWidth: CGFloat = 0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, ReadableWidth.margin(forWidth: availableWidth), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    /// 視窗寬度對應的左右邊界:超出 `maxWidth` 的部分平均分到兩側。
    public static func margin(forWidth width: CGFloat) -> CGFloat {
        max(0, (width - maxWidth) / 2)
    }
}

extension View {
    func readableContentWidth() -> some View {
        modifier(ReadableWidth())
    }
}
