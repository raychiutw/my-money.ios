import XCTest

/// 正式路徑(不帶 `-uiTesting`,也就是 TestFlight 版的 composition root)的 accent 色是品牌粉，不是系統藍。
///
/// 其他 UI 測試都帶 `-uiTesting`,走不到正式路徑。TestFlight 1.0 (36381212551) 的標題和按鈕都變成系統藍，
/// 原因是正式路徑的 `App.init()` 建立了 `EnvironmentValues()`。登入頁不會連網路，所以這裡直接啟動正式路徑。
final class BrandColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiveLaunchUsesBrandAccentColor() throws {
        let app = XCUIApplication()
        app.launch()
        let title = app.staticTexts["我的記帳本"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "沒有看到登入頁")

        let counts = try Self.tintedPixelCounts(in: title.screenshot().image)
        XCTAssertGreaterThan(counts.pink, 0, "登入頁標題沒有用品牌粉")
        XCTAssertEqual(counts.blue, 0, "登入頁標題是系統藍")
    }

    /// 紅色明顯多於藍色的像素算粉紅(淺色 #B8434D、深色 #FF8A8A),反過來算藍色(系統藍)。
    /// 背景和灰色文字的紅藍差不多，兩邊都不算。
    private static func tintedPixelCounts(in image: UIImage) throws -> (pink: Int, blue: Int) {
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

        var pink = 0
        var blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let bluePart = Int(pixels[index + 2])
            if red - bluePart > 64 {
                pink += 1
            } else if bluePart - red > 64 {
                blue += 1
            }
        }
        return (pink, blue)
    }
}
