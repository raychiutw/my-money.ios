import SwiftUI
#if os(iOS)
import UIKit
#endif

extension Color {
    /// 品牌粉紅:只用在 tab bar 目前所在的 tab(使用者要求，強化品牌識別)，其餘互動色維持單色(ADR-0007)。
    /// 四個變體:淺色 `#B8434D`(對白底 5.3:1)、深色 `#FF8A8A`、淺色增強對比 `#9E2F3A`、深色增強對比 `#FFB3B3`。
    static var brandPink: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let isHigh = traits.accessibilityContrast == .high
            switch (isDark, isHigh) {
            case (false, false): return UIColor(red: 0xB8 / 255, green: 0x43 / 255, blue: 0x4D / 255, alpha: 1)
            case (true, false): return UIColor(red: 0xFF / 255, green: 0x8A / 255, blue: 0x8A / 255, alpha: 1)
            case (false, true): return UIColor(red: 0x9E / 255, green: 0x2F / 255, blue: 0x3A / 255, alpha: 1)
            case (true, true): return UIColor(red: 0xFF / 255, green: 0xB3 / 255, blue: 0xB3 / 255, alpha: 1)
            }
        })
        #else
        Color(red: 0xB8 / 255, green: 0x43 / 255, blue: 0x4D / 255)
        #endif
    }
}
