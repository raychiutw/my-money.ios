import UIKit
import XCTest

/// 頂端遮罩(#205):往上捲時只有狀態列/靈動島那一條有遮罩,工具列那一排(篩選、記一筆、頭像)底下的內容不被糊掉。
/// 量法:捲動過程中,工具列那一排左邊(沒有按鈕的地方)的截圖對比(亮度標準差)——內容清楚時對比高,被模糊遮罩蓋住時對比低。
final class TopMaskUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 亮度標準差(0...1):內容有清楚的字或邊緣時大,被均勻的遮罩蓋住時小。
    private func contrast(of image: UIImage, region: CGRect) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        let rect = CGRect(
            x: region.minX * Double(cg.width), y: region.minY * Double(cg.height),
            width: region.width * Double(cg.width), height: region.height * Double(cg.height)
        ).integral
        let cropped = try XCTUnwrap(cg.cropping(to: rect))
        let width = cropped.width, height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        var sum = 0.0, sumSquares = 0.0
        let count = Double(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luma = (0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])) / 255
            sum += luma
            sumSquares += luma * luma
        }
        let mean = sum / count
        return (sumSquares / count - mean * mean).squareRoot()
    }

    /// 往上捲的過程中,工具列那一排左邊的最大對比(每捲 90pt 量一次)。
    @MainActor
    private func maxToolbarBandContrast(dark: Bool, tab: String) throws -> Double {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + (dark ? ["-uiTestingDark"] : [])
        app.launch()
        app.signInWithSampleAccount()
        app.tabBars.buttons[tab].tap()
        Thread.sleep(forTimeInterval: 1.5)
        var best = 0.0
        for step in 0..<8 {
            let image = app.screenshot().image
            // iPhone 17(402×874pt):狀態列約 62pt,工具列那一排約 62~125pt;按鈕在右邊(x > 45%),量左邊。
            let band = CGRect(x: 0.02, y: 70.0 / 874, width: 0.40, height: 40.0 / 874)
            let value = try contrast(of: image, region: band)
            best = max(best, value)
            if step == 3 || step == 5 {
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(tab) \(dark ? "深色" : "淺色") step\(step) 對比 \(String(format: "%.3f", value))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            ScrollSupport.nudge(app, by: 90)
            Thread.sleep(forTimeInterval: 0.4)
        }
        print("TOPMASK \(tab) dark=\(dark) maxContrast=\(best)")
        return best
    }

    @MainActor
    func testToolbarRowContentIsNotBlurredInDarkMode() throws {
        for tab in ["記帳", "統計"] {
            let best = try maxToolbarBandContrast(dark: true, tab: tab)
            XCTAssertGreaterThan(best, 0.06, "\(tab)(深色):工具列那一排底下的內容被遮罩糊掉了(最大對比 \(best))")
        }
    }

    @MainActor
    func testToolbarRowContentIsNotBlurredInLightMode() throws {
        for tab in ["記帳", "統計"] {
            let best = try maxToolbarBandContrast(dark: false, tab: tab)
            XCTAssertGreaterThan(best, 0.06, "\(tab)(淺色):工具列那一排底下的內容被遮罩糊掉了(最大對比 \(best))")
        }
    }
}
