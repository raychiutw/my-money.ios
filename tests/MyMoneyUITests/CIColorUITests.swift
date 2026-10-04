import XCTest

/// CI 色出現在更多地方(ADR-0009、#177):連結、可點的值、開關、進度、目標環。淺色與深色各驗一次。
/// 用像素分析數 CI 色(`CIPalette` 的填色與文字變體)的像素:文字細，數量門檻低;填色大面積，看占比。
final class CIColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
    }

    private static let appearances: [(XCUIDevice.Appearance, String)] = [(.light, "淺色"), (.dark, "深色")]

    @MainActor
    private func launch(_ appearance: XCUIDevice.Appearance, signedIn: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        if signedIn { app.signInWithSampleAccount() }
        return app
    }

    /// 登入頁的「立即註冊」是 CI 文字色，不是黑／白。
    @MainActor
    func testLoginLinkIsCIText() throws {
        for (appearance, name) in Self.appearances {
            let app = launch(appearance, signedIn: false)
            let link = app.buttons["login.register"]
            XCTAssertTrue(link.waitForExistence(timeout: 5), "\(name):沒有註冊連結")
            let stats = try PixelAnalysis.statistics(of: link.screenshot().image)
            XCTAssertGreaterThan(stats.ci, 30, "\(name):「立即註冊」不是 CI 文字色(CI 色像素 \(stats.ci))")
            app.terminate()
        }
    }

    /// 記一筆的帳戶列：還沒選時的佔位文字「請選擇扣款／存入帳戶」是 CI 文字色(可點的值)。
    @MainActor
    func testAccountPlaceholderIsCIText() throws {
        for (appearance, name) in Self.appearances {
            let app = launch(appearance)
            app.buttons["overview.add"].tap()
            let row = app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name):記一筆沒有帳戶列")
            let stats = try PixelAnalysis.statistics(of: row.screenshot().image)
            XCTAssertGreaterThan(stats.ci, 30, "\(name):帳戶列的佔位文字不是 CI 文字色(CI 色像素 \(stats.ci))")
            app.terminate()
        }
    }

    /// 儲蓄目標：進行中的進度條是 CI 色(達成的維持綠色);建立目標的「截止日」開關打開是 CI 色。
    @MainActor
    func testGoalProgressAndDeadlineSwitchAreCIColor() throws {
        for (appearance, name) in Self.appearances {
            let app = launch(appearance)
            app.openHomeEntry("goals")
            XCTAssertTrue(app.buttons["goals.add"].waitForExistence(timeout: 5), "\(name):沒有儲蓄目標頁")
            // 第一個進度條是沖繩旅遊(進行中);達成的那個維持綠色。
            let bar = app.progressIndicators.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5), "\(name):儲蓄目標頁沒有進度條")
            let progress = try PixelAnalysis.statistics(of: bar.screenshot().image)
            XCTAssertGreaterThan(progress.ci, 100, "\(name):進行中的進度條不是 CI 色(CI 色像素 \(progress.ci))")

            app.buttons["goals.add"].tap()
            let toggle = app.switches["截止日"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(name):建立目標沒有「截止日」開關")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1", "\(name):截止日開關沒有打開")
            // 開關的軌道在列的最右邊。
            let track = try PixelAnalysis.statistics(
                of: toggle.screenshot().image, region: CGRect(x: 0.82, y: 0.2, width: 0.16, height: 0.6)
            )
            XCTAssertGreaterThan(track.ciFraction, 0.25, "\(name):打開的開關不是 CI 色(CI 色占 \(track.ciFraction))")
            app.terminate()
        }
    }
}
