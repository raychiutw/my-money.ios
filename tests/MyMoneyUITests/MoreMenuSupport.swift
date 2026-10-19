import XCTest

/// ⋯ 選單(帳戶列、信用卡詳細頁、現金與活存詳細頁):點開再選項目。全 app 的列操作都是「點整列／左滑刪除／⋯」,長按沒有作用。
extension XCUIApplication {
    /// 帳戶頁:把某個帳戶列捲到看得見、點它右上角的 ⋯,再選選單項目。
    @MainActor
    func chooseFromAccountMenu(_ item: String, accountID: String, file: StaticString = #filePath, line: UInt = #line) {
        let more = buttons["accounts.more.\(accountID)"]
        XCTAssertTrue(ScrollSupport.revealFully(more, in: self), "帳戶頁找不到 \(accountID) 的 ⋯", file: file, line: line)
        more.tap()
        chooseMenuItem(item, file: file, line: line)
    }

    /// 詳細頁 toolbar 的 ⋯(信用卡是 `cardDetail.more`,現金與活存是 `accountDetail.more`)。
    @MainActor
    func chooseFromDetailMenu(_ item: String, identifier: String = "cardDetail.more", file: StaticString = #filePath, line: UInt = #line) {
        let more = buttons[identifier]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "詳細頁 toolbar 沒有 ⋯(\(identifier))", file: file, line: line)
        more.tap()
        chooseMenuItem(item, file: file, line: line)
    }

    @MainActor
    private func chooseMenuItem(_ item: String, file: StaticString, line: UInt) {
        let entry = buttons[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "⋯ 選單裡沒有「\(item)」", file: file, line: line)
        entry.tap()
    }

    /// ⋯ 選單裡有沒有這個項目(開了選單看一眼就收起來)。
    @MainActor
    func menuContains(_ item: String, opening more: XCUIElement) -> Bool {
        more.tap()
        let exists = buttons[item].firstMatch.waitForExistence(timeout: 2)
        // 點選單外面收起來(這一下只負責關選單),等項目消失才返回。
        windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        _ = buttons[item].firstMatch.waitForNonExistence(timeout: 3)
        return exists
    }
}
