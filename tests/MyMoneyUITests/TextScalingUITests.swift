import UIKit
import XCTest

/// 輸入欄的字要照系統字級縮放(#157 逐頁 HIG 審查):機器人模擬對話的輸入欄曾用 `.roundedBorder`,
/// 最大的無障礙字級下欄位和字還是原本的大小,旁邊的訊息卻放大了好幾倍;改掉樣式之後欄位變高了,字卻還是小的。
/// 所以不看欄位的高度,量欄位裡 placeholder 那行字的字高(墨跡),比較兩種字級下的字高。
final class TextScalingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBotInputFieldGrowsWithTextSize() {
        let normal = botInputTextHeight(contentSize: nil)
        let large = botInputTextHeight(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertGreaterThan(large, normal * 1.8, "無障礙字級下機器人輸入欄的字沒有跟著放大(預設字高 \(normal)pt,最大字級 \(large)pt)")
    }

    @MainActor
    private func botInputTextHeight(contentSize: String?) -> CGFloat {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        app.signInWithSampleAccount()
        // 剛登入時總覽還在載入，頭像按鈕點下去偶爾沒反應:沒打開就再點一次。
        let close = app.buttons["me.close"]
        for _ in 0..<3 where !close.exists {
            XCTAssertTrue(app.buttons["toolbar.me"].waitForExistence(timeout: 10), "沒有頭像按鈕")
            app.buttons["toolbar.me"].tap()
            _ = close.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(close.exists, "沒有打開「我的」")
        Thread.sleep(forTimeInterval: 1) // 等 sheet 滑完，不然剛打開時量到的位置是動畫中的
        // 大字級時入口在清單下面或上面，一步一步捲到整個露出來。
        let bot = app.buttons["機器人記帳"]
        XCTAssertTrue(ScrollSupport.revealFully(bot, in: app, inSheet: true), "沒有看到機器人記帳入口")
        bot.tap()
        let chat = app.buttons["模擬對話"]
        XCTAssertTrue(ScrollSupport.revealFully(chat, in: app, inSheet: true), "沒有看到模擬對話入口")
        chat.tap()
        let field = app.textFields["bot.draft"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "沒有看到輸入欄")
        // 量欄位裡 placeholder 那行字的字高(又短又淡,OCR 認不出來,改量墨跡):
        // 只看欄位中央,圓角外露出來的背景不算;placeholder 太長時系統會自動縮小字，這裡量的就是縮完的結果。
        let image = field.screenshot().image
        let cg = image.cgImage!
        let (w, h) = (cg.width, cg.height)
        let center = cg.cropping(to: CGRect(x: w * 8 / 100, y: h * 25 / 100, width: w * 84 / 100, height: h * 50 / 100))!
        let bands = (try? PixelAnalysis.inkBands(of: UIImage(cgImage: center), minimumDifference: 25)) ?? []
        let band = bands.max { $0.maxY - $0.minY < $1.maxY - $1.minY }
        XCTAssertNotNil(band, "量不到輸入欄裡的字")
        app.terminate()
        return CGFloat((band?.maxY ?? 0) - (band?.minY ?? 0)) / image.scale
    }
}
