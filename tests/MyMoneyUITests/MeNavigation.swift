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

extension XCUIElement {
    /// 這個元素顯示的所有文字:label、value 與子孫的靜態文字。
    /// 選擇列的值有時在 value、有時在子元素，只查 label 會漏掉。
    var displayedText: String {
        let value = (self.value as? String) ?? ""
        let children = staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        return [label, value, children].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 除錯用:列出這個元素底下所有按鈕的 identifier 與 label,失敗訊息裡看得到到底是哪幾顆。
    var buttonSummary: String {
        buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" }.joined(separator: ", ")
    }
}
