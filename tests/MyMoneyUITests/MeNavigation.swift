import XCTest

extension XCUIApplication {
    /// 點任何一個 tab 主頁面右上角的頭像，打開「我的」sheet(ADR-0004)。
    @MainActor
    func openMe() {
        buttons["toolbar.me"].tap()
    }

    /// 打開「我的」並切到「規劃」分頁:週期收支、儲蓄目標、現金流預測從這裡進去。
    @MainActor
    func openPlanning() {
        openMe()
        segmentedControls["me.page"].buttons["規劃"].tap()
    }
}
