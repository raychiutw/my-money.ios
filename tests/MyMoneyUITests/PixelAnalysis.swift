import UIKit
import XCTest

/// 解析 UI 測試截圖的像素:單色玻璃按鈕(#134)用「填滿的是不是黑／白」「有沒有藍字、粉紅字」判斷，不靠肉眼。
enum PixelAnalysis {
    struct Statistics {
        /// 亮度低於 25% 的像素占比(黑)。
        var darkFraction: Double
        /// 亮度高於 75% 的像素占比(白)。
        var lightFraction: Double
        /// 偏藍的像素數(系統藍;背景灰只差個位數)。
        var bluish: Int
        /// 接近品牌粉紅(任一個變體)的像素數。
        var brandPink: Int
    }

    /// 品牌粉紅(舊 AccentColor 的四個變體):互動元素不再用，只留在 logo、App icon 與頭像。
    static let brandPinks: [(red: Int, green: Int, blue: Int)] = [
        (0xB8, 0x43, 0x4D), (0xFF, 0x8A, 0x8A), (0x9E, 0x2F, 0x3A), (0xFF, 0xB3, 0xB3),
    ]
    static let pinkTolerance = 12
    /// 藍色比紅色多這麼多就算系統藍(iOS 的系統藍 B − R 都在 190 以上)。
    static let bluishGap = 64

    /// 元件中央的範圍(去掉圓角外露的背景):按鈕的填色與字用它判斷。
    static let center = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    /// 元件外緣有沒有外框(圓形底或邊線):沿著貼近邊緣的圓環取樣，有幾成的角度比背景(左上角那一點)亮或暗至少 `minimumDifference`。
    /// 有玻璃圓鈕時外緣一圈都有邊線或底色(接近 1);只有符號時外緣是背景(接近 0)。淺色玻璃跟背景只差幾個亮度(有些角度幾乎看不出來)，所以門檻很小,但沒有外框時外緣一圈就是背景本身，差距是 0 到 1。
    static func ringFrameFraction(of image: UIImage, minimumDifference: Int = 4) throws -> Double {
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
        func luma(_ x: Int, _ y: Int) -> Int {
            let index = (y * width + x) * 4
            return (Int(pixels[index]) * 299 + Int(pixels[index + 1]) * 587 + Int(pixels[index + 2]) * 114) / 1000
        }
        let background = luma(0, 0)
        let center = (Double(width) / 2, Double(height) / 2)
        var framed = 0
        var total = 0
        for degrees in stride(from: 0, to: 360, by: 5) {
            let angle = Double(degrees) * .pi / 180
            var found = false
            for fraction in stride(from: 0.38, through: 0.495, by: 0.01) {
                let radius = fraction * Double(width)
                let x = Int(center.0 + radius * cos(angle)), y = Int(center.1 + radius * sin(angle))
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                if abs(luma(x, y) - background) >= minimumDifference { found = true; break }
            }
            total += 1
            if found { framed += 1 }
        }
        return Double(framed) / Double(max(total, 1))
    }

    /// `region` 是要看的範圍，座標是圖片的比例(0 到 1);預設整張。
    static func statistics(of image: UIImage, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) throws -> Statistics {
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

        let minX = Int(region.minX * Double(width)), maxX = Int(region.maxX * Double(width))
        let minY = Int(region.minY * Double(height)), maxY = Int(region.maxY * Double(height))
        var total = 0, dark = 0, light = 0, bluish = 0, pink = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let index = (y * width + x) * 4
                let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
                total += 1
                let luma = (red * 299 + green * 587 + blue * 114) / 1000
                if luma < 64 { dark += 1 } else if luma > 192 { light += 1 }
                if brandPinks.contains(where: {
                    abs($0.red - red) <= pinkTolerance && abs($0.green - green) <= pinkTolerance && abs($0.blue - blue) <= pinkTolerance
                }) {
                    pink += 1
                } else if blue - red > bluishGap {
                    bluish += 1
                }
            }
        }
        let count = Double(max(total, 1))
        return Statistics(darkFraction: Double(dark) / count, lightFraction: Double(light) / count, bluish: bluish, brandPink: pink)
    }
}
