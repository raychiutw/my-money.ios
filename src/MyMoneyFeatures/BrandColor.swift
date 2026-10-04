import SwiftUI
#if os(iOS)
import UIKit
#endif

/// CI 色票(品牌粉紅紅，#175、ADR-0009)。純資料，不依賴 SwiftUI;對比用 WCAG 公式在單元測試驗證。
///
/// 分成兩種用途:
/// - **填色**(`fill`):✓、主要按鈕、選取、開關、進度。**淺色與深色同一個 `#E23C52`**(色相 352°)，所以兩種模式看起來是同一個品牌色;
///   反白字 4.2:1、深色底 5.0:1。增強對比時淺色改深紅 `#881121`(反白字 9.8:1)、深色改淺粉 `#FDA5B1`(配黑字 9.1:1)。
/// - **文字與線條**(`text`):連結、可點的值、tab 文字、勾勾。同色相，各自達 4.5:1 以上:淺色 `#AD1F32`(白底 7.0:1)、深色 `#F88191`(次層卡片 5.7:1)。
public enum CIPalette {
    public enum Appearance: CaseIterable, Sendable {
        case light, dark, lightIncreasedContrast, darkIncreasedContrast
    }

    public typealias RGB = AvatarPalette.RGB

    /// 填色。
    public static func fill(for appearance: Appearance) -> RGB {
        switch appearance {
        case .light, .dark: RGB(red: 0xE2, green: 0x3C, blue: 0x52)
        case .lightIncreasedContrast: RGB(red: 0x88, green: 0x11, blue: 0x21)
        case .darkIncreasedContrast: RGB(red: 0xFD, green: 0xA5, blue: 0xB1)
        }
    }

    /// 填色上的勾勾與字:除了深色增強對比的淺粉填色用黑字，其餘反白。
    public static func glyph(for appearance: Appearance) -> RGB {
        appearance == .darkIncreasedContrast ? RGB(red: 0, green: 0, blue: 0) : RGB(red: 255, green: 255, blue: 255)
    }

    /// 文字與線條。
    public static func text(for appearance: Appearance) -> RGB {
        switch appearance {
        case .light: RGB(red: 0xAD, green: 0x1F, blue: 0x32)
        case .dark: RGB(red: 0xF8, green: 0x81, blue: 0x91)
        case .lightIncreasedContrast: RGB(red: 0x84, green: 0x15, blue: 0x24)
        case .darkIncreasedContrast: RGB(red: 0xFD, green: 0xA5, blue: 0xB1)
        }
    }
}

extension Color {
    /// CI 填色(✓、主要按鈕、選取、開關、進度)。淺色與深色同一個顏色。
    static var ciFill: Color { dynamic(CIPalette.fill(for:)) }

    /// 填色上的勾勾與字。
    static var ciGlyph: Color { dynamic(CIPalette.glyph(for:)) }

    /// CI 文字與線條(連結、可點的值、tab 文字、勾勾)。
    static var ciText: Color { dynamic(CIPalette.text(for:)) }

    private static func dynamic(_ pick: @escaping (CIPalette.Appearance) -> CIPalette.RGB) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHigh = traits.accessibilityContrast == .high
            let rgb = pick(isDark ? (isHigh ? .darkIncreasedContrast : .dark) : (isHigh ? .lightIncreasedContrast : .light))
            return UIColor(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
        })
        #else
        let rgb = pick(.light)
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
        #endif
    }
}
