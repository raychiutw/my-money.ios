import XCTest

extension XCUIApplication {
    /// 記一筆的帳戶預設是空的(上游 ADR 0011、#109),儲存前要自己選:收起鍵盤、捲到帳戶列(在 16 格分類下面)、
    /// 點進清單頁、選一個帳戶(選了自動返回)。
    @MainActor
    func chooseQuickEntryAccount(_ name: String = "iOS 測試存款") {
        let done = buttons["完成"]
        if done.exists, done.isHittable { done.tap() }
        // 只在 collection view 裡找:sheet 後面底部 tab bar 也有一顆「帳戶」按鈕，但 tab bar 不是 collection view。
        let row = collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { swipeUp() }
        XCTAssertTrue(row.exists && row.isHittable, "記一筆沒有「帳戶」列")
        row.tap()
        let option = buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3), "沒有推入帳戶清單頁，或清單裡沒有「\(name)」")
        option.tap()
    }
}
