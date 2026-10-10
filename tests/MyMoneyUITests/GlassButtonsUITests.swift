import XCTest

/// 玻璃按鈕(#134、ADR-0007,#147、ADR-0008 修正):按鈕一律不填色，背景跟主題底色一樣，只有玻璃外框;
/// 沒有裸文字按鈕;sheet 的取消與確認是 ✕ 與 ✓ 兩顆一樣的玻璃圓鈕;需要文字的主要動作是玻璃膠囊(粗體字，不反白);
/// 選取的外框與勾勾、套用中的篩選用品牌粉紅(CI 色)，不填色。
final class GlassButtonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    func testSheetCloseIsGlassAndConfirmIsCIFilledInLight() throws {
        try assertSheetToolbarAndSelection(appearance: .light)
    }

    @MainActor
    func testSheetCloseIsGlassAndConfirmIsCIFilledInDark() throws {
        try assertSheetToolbarAndSelection(appearance: .dark)
    }

    /// 記一筆 sheet:✕ 玻璃圓鈕(VoiceOver 念「關閉」)與 ✓ 玻璃圓鈕(念「儲存」)是同一種樣式、都不填色，觸控範圍至少 44×44pt;
    /// 預設選取的分類格是粉紅外框加粉紅勾勾、不填色。
    @MainActor
    private func assertSheetToolbarAndSelection(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"

        app.buttons["overview.add"].tap()
        let close = app.buttons["關閉"]
        let save = app.buttons["quickEntry.save"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "\(name):沒有「關閉」(✕)")
        XCTAssertTrue(save.exists, "\(name):沒有確認(✓)")
        XCTAssertEqual(save.label, "儲存", "\(name):✓ 的 VoiceOver 標籤不是「儲存」")
        // 工具列的 ✕ 與 ✓ 是系統的玻璃圓鈕(視覺 36pt):系統的觸控範圍把圓鈕外擴到 44pt，這裡在圓鈕外 4pt 點一下也要點得到。
        for (button, label) in [(close, "關閉"), (save, "儲存")] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 36, "\(name):「\(label)」太小:\(button.frame)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 36, "\(name):「\(label)」太小:\(button.frame)")
        }
        XCTAssertFalse(app.navigationBars.buttons["取消"].exists, "\(name):sheet 還有文字的「取消」")

        // ✕ 是不填色的玻璃圓鈕:中央沒有大面積反白，外緣一圈有玻璃外框，叉叉看得到。
        try assertNotFilled(close, appearance: appearance, "\(name):✕ 被填色了")
        let closeRing = try PixelAnalysis.ringFrameFraction(of: close.screenshot().image)
        XCTAssertGreaterThan(closeRing, 0.3, "\(name):✕ 沒有玻璃外框(外緣一圈只有 \(closeRing) 跟背景不同)")
        // ✓ 是 CI 填色圓鈕、勾勾反白(ADR-0009、#176):中央大部分是 CI 色，勾勾(亮)看得到。
        var saved = try PixelAnalysis.statistics(of: save.screenshot().image, region: PixelAnalysis.center)
        for _ in 0..<6 where saved.ciFraction < 0.5 {
            Thread.sleep(forTimeInterval: 0.5)
            saved = try PixelAnalysis.statistics(of: save.screenshot().image, region: PixelAnalysis.center)
        }
        XCTAssertGreaterThan(saved.ciFraction, 0.5, "\(name):✓ 沒有填 CI 色(CI 色只占 \(saved.ciFraction))")
        XCTAssertGreaterThan(saved.lightFraction, 0.02, "\(name):✓ 的反白勾勾看不到(亮色只占 \(saved.lightFraction))")

        // 內嵌選擇列(歸屬):選取那一列的勾勾是品牌粉紅，沒選的那列沒有粉紅(ADR-0008)。
        let household = app.buttons["家庭公帳"], personal = app.buttons["個人私帳"]
        XCTAssertTrue(household.exists && personal.exists, "\(name):記一筆沒有歸屬的選擇列")
        XCTAssertTrue(household.isSelected, "\(name):歸屬預設不是家庭公帳")
        let selectedRow = try PixelAnalysis.statistics(of: household.screenshot().image)
        XCTAssertGreaterThan(selectedRow.ci, 30, "\(name):選取那列的勾勾不是品牌粉紅(粉紅像素 \(selectedRow.ci))")
        let otherRow = try PixelAnalysis.statistics(of: personal.screenshot().image)
        XCTAssertEqual(otherRow.ci, 0, "\(name):沒選的那列也有粉紅")

        // 預設選取的分類格(餐飲)是粉紅外框加粉紅勾勾、不填色:在表單最下面，要捲下去。
        // 金額欄一打開就對焦，鍵盤蓋住分類格:先收起。
        let done = app.keyboards.firstMatch.exists ? app.buttons["完成"].firstMatch : nil
        done?.tap()
        let category = app.buttons["餐飲"]
        for _ in 0..<8 where !(category.exists && category.isHittable) { app.swipeUp() }
        XCTAssertTrue(category.exists, "\(name):沒有找到分類格")
        XCTAssertTrue(category.isSelected, "\(name):餐飲不是選取狀態")
        try assertNotFilled(category, appearance: appearance, "\(name):選取的分類格又被填色了", minimumInk: 0.002)
        // 右上角是 CI 填色的勾勾徽章(ADR-0009、#177):角落有一塊 CI 色，不只是細細的勾勾。
        let badge = try PixelAnalysis.statistics(
            of: category.screenshot().image, region: CGRect(x: 0.72, y: 0.0, width: 0.28, height: 0.32)
        )
        XCTAssertGreaterThan(badge.ciFraction, 0.5, "\(name):選取的分類格右上角沒有 CI 色徽章(CI 色占 \(badge.ciFraction))")
        let selectedPixels = try PixelAnalysis.statistics(of: category.screenshot().image)
        XCTAssertGreaterThan(selectedPixels.ci, 200, "\(name):選取的分類格沒有品牌粉紅的外框與勾勾(粉紅像素 \(selectedPixels.ci))")
        let other = app.buttons["交通"]
        if other.exists, other.isHittable {
            let unselected = try PixelAnalysis.statistics(of: other.screenshot().image)
            XCTAssertLessThan(
                appearance == .dark ? unselected.lightFraction : unselected.darkFraction, 0.3, "\(name):沒選的分類格是填滿的"
            )
            XCTAssertEqual(unselected.ci, 0, "\(name):沒選的分類格也有粉紅")
        }

        // 在 ✕ 左邊緣外 4pt 點一下(44pt 的觸控範圍):要關得掉 sheet。
        let outsideEdge = CGVector(dx: -4 / close.frame.width, dy: 0.5)
        close.coordinate(withNormalizedOffset: outsideEdge).tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 3), "\(name):按「關閉」(圓鈕外 4pt)之後 sheet 沒有關閉，觸控範圍不到 44pt")
    }

    @MainActor
    func testMeSheetCloseIsUnfilledInLight() throws {
        try assertMeCloseIsUnfilled(appearance: .light)
    }

    @MainActor
    func testMeSheetCloseIsUnfilledInDark() throws {
        try assertMeCloseIsUnfilled(appearance: .dark)
    }

    /// 「我的」sheet 的 ✕ 跟其他 sheet 的 ✕ 一樣是不填色的玻璃圓鈕(#157:放在 `.confirmationAction` 會被系統自動填成主要動作鈕)。
    @MainActor
    private func assertMeCloseIsUnfilled(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"
        app.openMe()
        let close = app.buttons["me.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "\(name):「我的」沒有關閉鈕")
        try assertNotFilled(close, appearance: appearance, "\(name):「我的」的 ✕ 被填色了")
        let ring = try PixelAnalysis.ringFrameFraction(of: close.screenshot().image)
        XCTAssertGreaterThan(ring, 0.3, "\(name):「我的」的 ✕ 沒有玻璃外框(外緣一圈只有 \(ring) 跟背景不同)")
    }

    /// 機器人模擬對話的送出鈕是帶玻璃外框的圓鈕，不是裸圖示(#157);沒打字時停用，停用的玻璃鈕一樣有外框。
    @MainActor
    func testBotSendButtonHasGlassFrame() throws {
        let app = launchSignedIn()
        app.openMe()
        app.buttons["機器人記帳"].tap()
        app.buttons["模擬對話"].tap()
        let send = app.buttons["bot.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "沒有看到送出鈕")
        XCTAssertGreaterThanOrEqual(send.frame.width, 44, "送出鈕寬度不到 44pt:\(send.frame)")
        XCTAssertGreaterThanOrEqual(send.frame.height, 44, "送出鈕高度不到 44pt:\(send.frame)")
        let ring = try PixelAnalysis.ringFrameFraction(of: send.screenshot().image)
        XCTAssertGreaterThan(ring, 0.3, "送出鈕沒有玻璃外框(外緣一圈只有 \(ring) 跟背景不同)")
    }

    /// 區塊標題沒有「管理」「全部」這類裸文字按鈕，改成「…」玻璃圓鈕(視覺 32pt、點擊範圍至少 44pt)，點開選單。
    @MainActor
    func testSectionHeadersUseMoreMenusInsteadOfTextButtons() throws {
        let app = launchSignedIn()
        let accountsMore = app.buttons["overview.accounts.more"]
        for _ in 0..<5 where !(accountsMore.exists && accountsMore.isHittable) { app.swipeUp() }
        XCTAssertTrue(accountsMore.exists, "帳戶區塊標題沒有「…」")
        XCTAssertGreaterThanOrEqual(accountsMore.frame.width, 44, "「…」寬度不到 44pt:\(accountsMore.frame)")
        XCTAssertGreaterThanOrEqual(accountsMore.frame.height, 44, "「…」高度不到 44pt:\(accountsMore.frame)")
        XCTAssertEqual(accountsMore.label, "帳戶的更多動作")

        XCTAssertFalse(app.buttons["管理"].exists, "還有裸文字按鈕「管理」")
        XCTAssertFalse(app.buttons["全部"].exists, "還有裸文字按鈕「全部」")
    }

    @MainActor
    func testMoreMenusHaveNoFrameInLight() throws {
        try assertMoreMenusHaveNoFrame(appearance: .light)
    }

    @MainActor
    func testMoreMenusHaveNoFrameInDark() throws {
        try assertMoreMenusHaveNoFrame(appearance: .dark)
    }

    /// 區塊標題的「…」只剩符號、沒有外框(使用者要求，#137):元件外緣一圈跟背景一樣;有玻璃圓鈕時外緣一圈都有邊線或底色。
    /// 可點範圍仍至少 44×44pt，選單項目還在。
    @MainActor
    private func assertMoreMenusHaveNoFrame(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"
        for identifier in ["overview.accounts.more"] {
            let more = app.buttons[identifier]
            for _ in 0..<8 where !(more.exists && more.isHittable) { app.swipeUp() }
            XCTAssertTrue(more.exists, "\(name):沒有 \(identifier)")
            XCTAssertGreaterThanOrEqual(more.frame.width, 44, "\(name):\(identifier) 寬度不到 44pt:\(more.frame)")
            XCTAssertGreaterThanOrEqual(more.frame.height, 44, "\(name):\(identifier) 高度不到 44pt:\(more.frame)")
            let image = more.screenshot().image
            let ring = try PixelAnalysis.ringFrameFraction(of: image)
            XCTAssertLessThan(ring, 0.1, "\(name):\(identifier) 還有外框(外緣一圈有 \(ring) 跟背景不同)")
            // 符號本身(三個點)還在:元件中央有跟背景不同的像素。
            let symbol = try PixelAnalysis.statistics(of: image, region: PixelAnalysis.center)
            XCTAssertGreaterThan(symbol.darkFraction + symbol.lightFraction, 0.005, "\(name):\(identifier) 連符號都看不到")
        }
        app.buttons["overview.accounts.more"].tap()
        XCTAssertTrue(app.buttons["管理帳戶"].waitForExistence(timeout: 3), "\(name):選單沒有「管理帳戶」")
    }

    @MainActor
    func testTransferCapsuleIsCIFilledInLight() throws {
        try assertTransferCapsule(appearance: .light)
    }

    @MainActor
    func testTransferCapsuleIsCIFilledInDark() throws {
        try assertTransferCapsule(appearance: .dark)
    }

    /// 需要文字的主要動作(帳戶頁的「ATM 提款／轉帳」)是 CI 填色的膠囊、反白粗體字(ADR-0009、#176)。
    @MainActor
    private func assertTransferCapsule(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        app.tabBars.buttons["帳戶"].tap()
        let transfer = app.buttons["accounts.transfer"]
        for _ in 0..<5 where !(transfer.exists && transfer.isHittable) { app.swipeUp() }
        XCTAssertTrue(transfer.exists, "沒有「ATM 提款／轉帳」膠囊")
        let name = appearance == .dark ? "深色" : "淺色"
        XCTAssertGreaterThanOrEqual(transfer.frame.height, 44, "\(name):膠囊高度不到 44pt:\(transfer.frame)")
        var stats = try PixelAnalysis.statistics(of: transfer.screenshot().image, region: PixelAnalysis.center)
        for _ in 0..<6 where stats.ciFraction < 0.5 {
            Thread.sleep(forTimeInterval: 0.5)
            stats = try PixelAnalysis.statistics(of: transfer.screenshot().image, region: PixelAnalysis.center)
        }
        XCTAssertGreaterThan(stats.ciFraction, 0.5, "\(name):主要膠囊沒有填 CI 色(CI 色只占 \(stats.ciFraction))")
        XCTAssertGreaterThan(stats.lightFraction, 0.01, "\(name):膠囊上的反白字看不到")
    }

    @MainActor
    func testActiveFilterIsAHollowBrandPinkCircleInLight() throws {
        try assertActiveFilter(appearance: .light)
    }

    @MainActor
    func testActiveFilterIsAHollowBrandPinkCircleInDark() throws {
        try assertActiveFilter(appearance: .dark)
    }

    /// 套用中的篩選(#147):圖示是品牌粉紅(CI 色)的空心圓圈，不是反白填滿的圓;沒套用時是一般的圖示、沒有粉紅。
    @MainActor
    private func assertActiveFilter(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"
        let filter = app.buttons["overview.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "\(name):總覽沒有視角篩選")

        let inactive = try PixelAnalysis.statistics(of: filter.screenshot().image, region: PixelAnalysis.center)
        XCTAssertEqual(inactive.ci, 0, "\(name):沒套用篩選卻有粉紅")

        filter.tap()
        let household = app.buttons["家庭公帳"]
        XCTAssertTrue(household.waitForExistence(timeout: 3), "\(name):視角選單沒有「家庭公帳」")
        household.tap()
        XCTAssertEqual(filter.value as? String, "家庭公帳", "\(name):沒有切到家庭公帳")
        var active = try PixelAnalysis.statistics(of: filter.screenshot().image, region: PixelAnalysis.center)
        for _ in 0..<6 where active.ci < 30 {
            Thread.sleep(forTimeInterval: 0.5)
            active = try PixelAnalysis.statistics(of: filter.screenshot().image, region: PixelAnalysis.center)
        }
        XCTAssertGreaterThan(active.ci, 30, "\(name):套用中的篩選圖示沒有品牌粉紅(粉紅像素 \(active.ci))")
        // 空心:中央沒有大面積反白(以前是白色或黑色的實心圓)。
        XCTAssertLessThan(
            appearance == .dark ? active.lightFraction : active.darkFraction, 0.3, "\(name):套用中的篩選圖示又變成反白填滿的實心圓"
        )
    }

    // MARK: 輔助

    /// 不填色(#147):中央區域沒有大面積的反白(淺色黑、深色白),而且字或圖示看得到(有最少的墨跡)。
    /// 切換外觀、動畫剛結束時截圖可能還是舊的樣子，最多重試幾次。
    @MainActor
    private func assertNotFilled(
        _ element: XCUIElement, appearance: XCUIDevice.Appearance, _ message: String, maxFill: Double = 0.3, minimumInk: Double = 0.003
    ) throws {
        var fill = 1.0
        var ink = 0.0
        for _ in 0..<6 {
            let stats = try PixelAnalysis.statistics(of: element.screenshot().image, region: PixelAnalysis.center)
            // 字與圖示是主要文字色(淺色黑、深色白);填色時同一種顏色會鋪滿整個中央區域。
            fill = appearance == .dark ? stats.lightFraction : stats.darkFraction
            ink = fill
            if fill < maxFill, ink > minimumInk { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("\(message)(\(appearance == .dark ? "白" : "黑")色占 \(fill),要在 \(minimumInk) 到 \(maxFill) 之間:太高是被填色，太低是看不到字或圖示)")
    }

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        return app
    }
}
