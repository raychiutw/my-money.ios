import XCTest

extension XCUIApplication {
    /// 點任何一個 tab 主頁面右上角的頭像，打開「我的」sheet(ADR-0004)。
    @MainActor
    func openMe() {
        buttons["toolbar.me"].tap()
    }

    /// 從總覽的功能入口進去(#178;週期收支、儲蓄目標、現金流預測原本在「我的」的「規劃」分頁)。
    /// `identifier` 是入口的 destination(`home.entry.<identifier>`):ledger、accounts、creditCards、household、statistics、
    /// recurring、goals、forecast。入口可能在畫面下方(大字級更下面),先捲到整個看得到再點。
    @MainActor
    func openHomeEntry(_ identifier: String) {
        let tab = tabBars.buttons["總覽"]
        if tab.exists, !tab.isSelected { tab.tap() }
        // 載入完成的記號(骨架屏沒有組成一行);載入完才捲,不然會在骨架屏上亂捲。
        _ = staticTexts["overview.composition"].waitForExistence(timeout: 10)
        let entry = buttons["home.entry.\(identifier)"]
        XCTAssertTrue(ScrollSupport.revealFully(entry, in: self), "總覽找不到「\(identifier)」入口，或捲不到整個露出")
        entry.tap()
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
