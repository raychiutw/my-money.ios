import XCTest

extension XCUIApplication {
    /// 點任何一個 tab 主頁面右上角的頭像，打開「我的」sheet(ADR-0004)。
    @MainActor
    func openMe() {
        buttons["toolbar.me"].tap()
    }

    /// 從總覽的功能入口進去(#178;週期收支、儲蓄目標、現金流預測原本在「我的」的「規劃」分頁)。
    /// `identifier` 是入口的 destination(`home.entry.<identifier>`):recurring、goals、forecast(#196:tab 已有的功能不再有入口)。入口可能在畫面下方(大字級更下面),先捲到整個看得到再點。
    @MainActor
    func openHomeEntry(_ identifier: String) {
        let tab = tabBars.buttons["總覽"]
        if tab.exists, !tab.isSelected { tab.tap() }
        // 載入完成的記號(骨架屏沒有組成一行);載入完才捲,不然會在骨架屏上亂捲。
        _ = descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        let entry = buttons["home.entry.\(identifier)"]
        XCTAssertTrue(ScrollSupport.revealFully(entry, in: self), "總覽找不到「\(identifier)」入口，或捲不到整個露出")
        entry.tap()
    }
}

extension XCUIApplication {
    /// 家庭頁:點成員列進該成員的代墊詳細頁(#246)。
    @MainActor
    func openMemberDetail(_ memberID: String) {
        let row = memberRow(memberID)
        row.tap()
    }

    /// 家庭頁成員列右側 ⋯ 的項目(#274:明細、沖銷、標記處理、移除);回傳有沒有點到(項目不在選單裡就是 `false`)。
    @MainActor
    @discardableResult
    func chooseMemberMenuItem(_ item: String, memberID: String) -> Bool {
        let row = memberRow(memberID)
        let more = buttons["household.more.\(memberID)"]
        XCTAssertTrue(ScrollSupport.revealFully(more, in: self) || row.exists, "家庭頁找不到成員「\(memberID)」的 ⋯")
        more.tap()
        let entry = buttons[item].firstMatch
        guard entry.waitForExistence(timeout: 3) else {
            // 沒有這個項目:點選單外面收起來。
            windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            return false
        }
        entry.tap()
        return true
    }

    /// 家庭頁成員列的 ⋯ 選單裡有沒有這個項目(開了看一眼就收起來)。
    @MainActor
    func memberMenuContains(_ item: String, memberID: String) -> Bool {
        let more = buttons["household.more.\(memberID)"]
        XCTAssertTrue(ScrollSupport.revealFully(more, in: self), "家庭頁找不到成員「\(memberID)」的 ⋯")
        return menuContains(item, opening: more)
    }

    /// 成員列捲到看得見。
    @MainActor
    private func memberRow(_ memberID: String) -> XCUIElement {
        let row = descendants(matching: .any)["household.member.\(memberID)"]
        _ = row.waitForExistence(timeout: 5)
        for _ in 0..<8 where !(row.exists && row.isHittable) { swipeUp() }
        XCTAssertTrue(row.exists, "家庭頁找不到成員「\(memberID)」的列")
        return row
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
