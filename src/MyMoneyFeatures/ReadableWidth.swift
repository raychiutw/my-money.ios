import SwiftUI
#if os(iOS)
import UIKit
#endif

/// iPad 上內容限制在可讀寬度並置中(#173、HIG Layout:內容不要隨視窗拉伸)。
///
/// 清單的列左邊是名稱、右邊是金額,在 iPad 直向(820pt)會隔七百多 pt,眼睛要跨整個畫面才對得上;登入的欄位和按鈕也有 800pt 寬。
/// 用 `contentMargins(…, for: .scrollContent)` 把捲動內容左右推進去:背景與捲動範圍仍撐滿整個視窗;
/// 視窗比 `maxWidth` 窄(iPhone、Split View)時邊界是 0,版面不變。
/// iPad 橫向時 sidebar 浮在內容左邊:清單(UIKit 的 collection view)的 frame 其實從視窗最左邊開始、延伸到 sidebar 底下,
/// 而這個 modifier 量到的 view 只有 sidebar 右邊那一塊(實測清單 280…1376、view 是 280…1376 的詳細欄)。
/// `contentMargins` 是相對清單的 frame,所以左邊要加上 view 的左緣離視窗左緣的距離(sidebar 的寬度),內容才置中在看得到的那一欄。
/// 掛在 tab 的內容或登入頁上,往下的捲動容器(含推入的頁面)都套用;sheet 是另一個呈現,不受影響(它們本來就是窄的)。
public struct ReadableWidth: ViewModifier {
    /// 內容最大寬度(pt):約 700,跟系統的可讀內容寬度同一個量級。
    public static let maxWidth: CGFloat = 700

    /// 這個 view 的寬度(看得到的那一欄),以及它的左緣離視窗左緣多遠(橫向的 sidebar 寬度;沒有 sidebar 是 0)。
    @State private var layout = Layout(width: 0, leading: 0)

    private struct Layout: Equatable {
        var width: CGFloat
        var leading: CGFloat
    }

    public init() {}

    @ViewBuilder
    public func body(content: Content) -> some View {
        if Self.isPad {
            let margin = ReadableWidth.margin(forWidth: layout.width)
            content
                .contentMargins(.leading, layout.leading + margin, for: .scrollContent)
                .contentMargins(.trailing, margin, for: .scrollContent)
                .onGeometryChange(for: Layout.self) { proxy in
                    Layout(width: proxy.size.width, leading: proxy.frame(in: .global).minX)
                } action: { layout = $0 }
        } else {
            // iPhone 不需要:不套 `contentMargins`(實測連邊界 0 也會改變清單內容的內距，金額對齊的 UI 測試因此失敗)。
            content
        }
    }

    /// 只有 iPad 才限制寬度。這是裝置的種類，不會在執行中改變，所以兩個分支不會互相切換(不會丟掉畫面狀態)。
    private static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
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
