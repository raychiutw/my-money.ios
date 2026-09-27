// 用 Icon Composer 內附的 ictool 算出 AppIcon.icon 各外觀的預覽圖。
//
// 用法(在 repo 根目錄):
//     swift design/app-icon/tools/render-previews.swift
//
// 產出(都在 `preview/`):
// - 六種外觀各一張 512×512:default、dark、clear-light、clear-dark、tinted-light、tinted-dark。
// - `sizes.png`:同樣六種外觀，各以 40、58、87、120、180 px 直接由 ictool 算圖後原尺寸排在一起，
//   用來檢查小尺寸是否清楚。淺色外觀排在淺灰底上，深色外觀排在深灰底上。
//
// 像素都是 ictool 算的。ictool 輸出 16-bit Display P3 PNG,這裡只轉成 8-bit(色彩描述檔不變)來縮小檔案，
// sizes.png 則只是把 ictool 的輸出原尺寸貼到同一張底圖上，不縮放。
//
// ictool 預設從 `xcode-select -p` 指向的 Xcode 裡找;要指定其他位置時設定環境變數 ICTOOL。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let appIconDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // tools/
    .deletingLastPathComponent()  // app-icon/
let iconDocument = appIconDir.appendingPathComponent("../../src/App/MyMoney/AppIcon.icon").standardizedFileURL
let previewDir = appIconDir.appendingPathComponent("preview")

/// (ictool 的 rendition 名稱, 輸出檔名, 是否為深色外觀)
let renditions: [(name: String, file: String, isDark: Bool)] = [
    ("Default", "default", false),
    ("Dark", "dark", true),
    ("ClearLight", "clear-light", false),
    ("ClearDark", "clear-dark", true),
    ("TintedLight", "tinted-light", false),
    ("TintedDark", "tinted-dark", true),
]
let previewSize = 512
/// 20 pt @2x、29 pt @2x、29 pt @3x、60 pt @2x、60 pt @3x
let smallSizes = [40, 58, 87, 120, 180]

// MARK: - ictool

func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "render-previews", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "\(executable) 失敗:\(output)",
        ])
    }
    return output
}

func locateICTool() throws -> String {
    if let path = ProcessInfo.processInfo.environment["ICTOOL"] { return path }
    let developerDir = try run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
    return URL(fileURLWithPath: developerDir)
        .deletingLastPathComponent()  // Contents/
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
}

let ictool = try locateICTool()
print("ictool:", ictool, try run(ictool, ["--version"]).replacingOccurrences(of: "\n", with: " "))

let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("app-icon-previews-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func render(_ rendition: String, size: Int) throws -> CGImage {
    let output = scratch.appendingPathComponent("\(rendition)-\(size).png")
    _ = try run(ictool, [
        iconDocument.path, "--export-image",
        "--output-file", output.path,
        "--platform", "iOS",
        "--rendition", rendition,
        "--width", "\(size)", "--height", "\(size)",
        "--scale", "1",
    ])
    guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw NSError(domain: "render-previews", code: 1, userInfo: [NSLocalizedDescriptionKey: "讀不到 \(output.path)"]) }
    return image
}

// MARK: - 8-bit PNG

let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "render-previews", code: 2) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "render-previews", code: 3) }
}

/// 16-bit 轉 8-bit,色彩空間維持 Display P3。
func eightBit(_ image: CGImage) -> CGImage {
    let context = makeContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()!
}

// MARK: - 產出

try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

for rendition in renditions {
    let url = previewDir.appendingPathComponent("\(rendition.file).png")
    try writePNG(eightBit(try render(rendition.name, size: previewSize)), to: url)
    print("preview/\(rendition.file).png")
}

let padding = 16
let rowHeight = smallSizes.max()! + padding * 2
let sheetWidth = smallSizes.reduce(padding) { $0 + $1 + padding }
let sheetHeight = rowHeight * renditions.count
let sheet = makeContext(width: sheetWidth, height: sheetHeight)
for (row, rendition) in renditions.enumerated() {
    // CoreGraphics 的原點在左下，第 0 列要畫在最上面
    let rowBottom = sheetHeight - (row + 1) * rowHeight
    let background = rendition.isDark
        ? CGColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
        : CGColor(srgbRed: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
    sheet.setFillColor(background)
    sheet.fill(CGRect(x: 0, y: rowBottom, width: sheetWidth, height: rowHeight))
    var x = padding
    for size in smallSizes {
        let image = try render(rendition.name, size: size)
        // 底部對齊，原尺寸貼上，不縮放
        sheet.draw(image, in: CGRect(x: x, y: rowBottom + padding, width: size, height: size))
        x += size + padding
    }
}
try writePNG(sheet.makeImage()!, to: previewDir.appendingPathComponent("sizes.png"))
print("preview/sizes.png")
