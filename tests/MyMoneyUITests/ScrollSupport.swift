import XCTest

/// 把元素捲到整個都看得到(不被導覽列或浮在內容上的 tab bar 蓋住),截圖分析才準。
/// 一次只輕輕拖一小段，不會像 `swipeUp` 一次捲過頭來回震盪。
enum ScrollSupport {
    /// 回傳是不是已經整個露出。找不到或捲不到時回傳 false。
    @MainActor
    static func revealFully(_ element: XCUIElement, in app: XCUIApplication, inSheet: Bool = false) -> Bool {
        // sheet 蓋住 tab bar:底下只有畫面的下緣。
        let tabBar = inSheet ? app.tabBars.element(boundBy: 99) : app.tabBars.firstMatch
        let window = app.windows.firstMatch
        let top = window.frame.minY + 130
        for _ in 0..<40 {
            let bottom = (tabBar.exists ? tabBar.frame.minY : window.frame.maxY) - 8
            guard element.exists else {
                nudge(app, by: 260)
                continue
            }
            if element.frame.minY < top {
                nudge(app, by: element.frame.minY - top - 16)
            } else if element.frame.maxY > bottom {
                nudge(app, by: min(element.frame.maxY - bottom + 16, element.frame.minY - top))
            } else {
                return true
            }
        }
        return false
    }

    /// 內容往上(正)或往下(負)捲 `distance` 點。
    @MainActor
    static func nudge(_ app: XCUIApplication, by distance: CGFloat) {
        let window = app.windows.firstMatch
        let height = window.frame.height
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6 - distance / height))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}
