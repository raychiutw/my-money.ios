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

    /// 一條橫向的文字帶(同一列文字所在的 y 範圍)與它墨跡的左右邊界;座標是畫素。
    struct InkBand {
        var minY: Int
        var maxY: Int
        var minX: Int
        var maxX: Int
        /// 有墨跡的 x 座標(由小到大、不重複)。
        var inkColumns: [Int]

        /// 水平方向相隔至少 `minGap` 畫素的墨跡群數(標題、金額、資產帳戶各算一群)。
        func clusters(minGap: Int) -> Int {
            1 + zip(inkColumns, inkColumns.dropFirst()).filter { $1 - $0 >= minGap }.count
        }
    }

    /// 交易列之類的版面檢查:把截圖切成一條一條有墨跡(跟背景亮度差夠大)的橫帶，回傳每一條的左右邊界與墨跡群數。
    /// 背景取左邊緣中間那一點(列的左內距沒有任何字)。
    /// `skippingLeadingCluster`:先略過最左邊那一群墨跡(列前面的分類圖示。它垂直置中，會把上下兩行連在一起)。
    static func inkBands(
        of image: UIImage, minimumDifference: Int = 60, skippingLeadingCluster: Bool = false, leadingGap: Int = 24
    ) throws -> [InkBand] {
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
        let background = luma(2, height / 2)
        var startX = 0
        if skippingLeadingCluster {
            var inkColumns: [Int] = []
            for x in 0..<width where (0..<height).contains(where: { abs(luma(x, $0) - background) >= minimumDifference }) {
                inkColumns.append(x)
            }
            for (previous, next) in zip(inkColumns, inkColumns.dropFirst()) where next - previous >= leadingGap {
                startX = next
                break
            }
        }
        // 每一個 y 的墨跡 x 座標。
        var bands: [InkBand] = []
        var current: (minY: Int, maxY: Int, xs: [Int])?
        func close() {
            guard let band = current else { return }
            current = nil
            guard band.maxY - band.minY >= 5, let first = band.xs.min(), let last = band.xs.max() else { return }
            bands.append(InkBand(minY: band.minY, maxY: band.maxY, minX: first, maxX: last, inkColumns: Set(band.xs).sorted()))
        }
        for y in 0..<height {
            var xs: [Int] = []
            for x in startX..<width where abs(luma(x, y) - background) >= minimumDifference { xs.append(x) }
            if xs.isEmpty {
                close()
            } else if var band = current {
                band.maxY = y
                band.xs += xs
                current = band
            } else {
                current = (y, y, xs)
            }
        }
        close()
        return bands
    }
}
