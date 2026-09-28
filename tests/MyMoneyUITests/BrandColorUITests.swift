import XCTest

/// 正式路徑(不帶 `-uiTesting`,也就是 TestFlight 版的 composition root)的 accent 色是品牌粉，不是系統藍。
///
/// 其他 UI 測試都帶 `-uiTesting`,走不到正式路徑。TestFlight 1.0 (36381212551) 的標題和按鈕都變成系統藍，
/// 原因是正式路徑的 `App.init()` 建立了 `EnvironmentValues()`。登入頁不會連網路，所以這裡直接啟動正式路徑。
final class BrandColorUITests: XCTestCase {
    /// AccentColor 的四個變體(DESIGN.md「顏色」):淺色、深色、淺色 + 增強對比、深色 + 增強對比。
    private static let brandAccents: [(red: Int, green: Int, blue: Int)] = [
        (0xB8, 0x43, 0x4D), (0xFF, 0x8A, 0x8A), (0x9E, 0x2F, 0x3A), (0xFF, 0xB3, 0xB3),
    ]
    /// 每個色版跟 accent 差多少以內算同一個顏色。標題是粗體 largeTitle,字的內部有很多正好是 accent 的像素。
    private static let accentTolerance = 12
    /// 藍色比紅色多這麼多就算系統藍(iOS 的系統藍 B − R 都在 190 以上;背景 #F2F2F7 只差 5)。
    private static let bluishGap = 64

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiveLaunchUsesBrandAccentColor() throws {
        let app = XCUIApplication()
        app.launch()
        // 正式路徑沒有 -resetSession:模擬器裡如果手動登入過，會直接進 tab 外殼並連 prod,這時不跑。
        if app.tabBars.firstMatch.waitForExistence(timeout: 2) {
            throw XCTSkip("模擬器的正式 Keychain 裡有 session,登入頁看不到;請先登出或清除模擬器")
        }
        let title = app.staticTexts["我的記帳本"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "沒有看到登入頁")

        let counts = try Self.pixelCounts(in: title.screenshot().image)
        XCTAssertGreaterThan(counts.accent, 0, "登入頁標題沒有用品牌粉")
        XCTAssertEqual(counts.bluish, 0, "登入頁標題是系統藍")
    }

    /// 接近任一個品牌 accent 的像素數，以及偏藍的像素數。
    private static func pixelCounts(in image: UIImage) throws -> (accent: Int, bluish: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn, "沒辦法讀取截圖的像素")

        var accent = 0
        var bluish = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            if brandAccents.contains(where: {
                abs($0.red - red) <= accentTolerance && abs($0.green - green) <= accentTolerance
                    && abs($0.blue - blue) <= accentTolerance
            }) {
                accent += 1
            } else if blue - red > bluishGap {
                bluish += 1
            }
        }
        return (accent, bluish)
    }
}
