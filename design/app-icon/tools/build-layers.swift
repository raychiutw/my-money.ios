// 由 lucide 的 book-heart.svg 產生 Icon Composer 的前景圖層。
//
// 用法(在 repo 根目錄):
//     swift design/app-icon/tools/build-layers.swift
//
// 做的事:
// 1. 讀 `upstream/lucide-book-heart.svg`,取出書與愛心兩條 path。
// 2. 用 CoreGraphics 把 stroke 轉成填色外框(HIG:「Outline artwork」),
//    線寬改成 app icon 用的粗細，愛心改成實心。
// 3. 放大、置中到 1024×1024 的畫布，輸出到 `AppIcon.icon/Assets/`。
//
// 只產生前景 SVG。背景色、Liquid Glass 效果與各外觀的顏色都在 `AppIcon.icon/icon.json` 裡設定。

import CoreGraphics
import Foundation

// MARK: - 設計參數

/// 畫布邊長(px)。iOS app icon 的規格是 1024×1024。
let canvas: CGFloat = 1024

/// 1 個 lucide 單位(24×24 格線裡的 1)在畫布上等於幾 px。
/// 書本身高 20 個單位，乘上 30 是 600 px,加上線寬後約佔畫布高度的 66%。
let unit: CGFloat = 30

/// 線寬，單位是 lucide 單位。lucide 原本是 2(給 24 px 的 UI 圖示用)。
/// app icon 最小會縮到 40 px(20 pt @2x),這時整本書只剩約 26 px 高，
/// 原本的 2 只有約 2.3 px,在 Liquid Glass 的高光與模糊下會變得太細。
/// 加粗到 2.5(約 2.9 px),1024 px 時是 75 px。
let strokeWidth: CGFloat = 2.5

// MARK: - 路徑

let appIconDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // tools/
    .deletingLastPathComponent()  // app-icon/
let upstreamSVG = appIconDir.appendingPathComponent("upstream/lucide-book-heart.svg")
let assetsDir = appIconDir.appendingPathComponent("AppIcon.icon/Assets")

// MARK: - 讀取 lucide 的 path

func lucidePaths() throws -> [String] {
    let svg = try String(contentsOf: upstreamSVG, encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"<path d="([^"]+)""#)
    let range = NSRange(svg.startIndex..., in: svg)
    let paths = regex.matches(in: svg, range: range).map { match in
        String(svg[Range(match.range(at: 1), in: svg)!])
    }
    guard paths.count == 2 else {
        throw NSError(domain: "build-layers", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "預期 lucide book-heart.svg 有 2 條 path(書、愛心),實際是 \(paths.count) 條",
        ])
    }
    return paths
}

// MARK: - SVG path data 解析

/// 只支援 lucide book-heart 用到的指令:M、L、H、V、A、Z(大小寫都支援)。
struct PathDataParser {
    private let chars: [Character]
    private var index = 0

    init(_ data: String) { chars = Array(data) }

    private mutating func skipSeparators() {
        while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline {
            index += 1
        }
    }

    private mutating func command() -> Character? {
        skipSeparators()
        guard index < chars.count, chars[index].isLetter else { return nil }
        defer { index += 1 }
        return chars[index]
    }

    private mutating func number() -> CGFloat {
        skipSeparators()
        var text = ""
        if chars[index] == "-" || chars[index] == "+" {
            text.append(chars[index])
            index += 1
        }
        var seenDot = false
        while index < chars.count {
            let c = chars[index]
            if c.isNumber {
                text.append(c)
            } else if c == ".", !seenDot {
                seenDot = true
                text.append(c)
            } else {
                break
            }
            index += 1
        }
        return CGFloat(Double(text)!)
    }

    private mutating func flag() -> Bool {
        skipSeparators()
        defer { index += 1 }
        return chars[index] == "1"
    }

    private mutating func atEnd() -> Bool {
        skipSeparators()
        return index >= chars.count
    }

    mutating func parse() -> CGMutablePath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var cmd: Character = "M"
        while !atEnd() {
            if let next = command() { cmd = next }
            let relative = cmd.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch cmd.uppercased() {
            case "M":
                current = point(number(), number())
                subpathStart = current
                path.move(to: current)
                cmd = relative ? "l" : "L"  // M 之後的座標視為 L
            case "L":
                current = point(number(), number())
                path.addLine(to: current)
            case "H":
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V":
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "A":
                let rx = number(), ry = number(), rotation = number()
                let largeArc = flag(), sweep = flag()
                let end = point(number(), number())
                addArc(to: path, from: current, to: end, rx: rx, ry: ry,
                       rotationDegrees: rotation, largeArc: largeArc, sweep: sweep)
                current = end
            case "Z":
                path.closeSubpath()
                current = subpathStart
            default:
                fatalError("不支援的 path 指令:\(cmd)")
            }
        }
        return path
    }
}

/// SVG 的 endpoint arc 轉成三次 Bézier(SVG 1.1 規格附錄 F.6.5 的 center parameterization)。
func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
            rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool) {
    var rx = abs(rx0), ry = abs(ry0)
    let phi = rotationDegrees * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
        rx *= sqrt(lambda)
        ry *= sqrt(lambda)
    }
    let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var coefficient = sqrt(max(0, numerator / denominator))
    if largeArc == sweep { coefficient = -coefficient }
    let cx1 = coefficient * (rx * y1 / ry)
    let cy1 = coefficient * -(ry * x1 / rx)
    let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
    let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var deltaTheta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep, deltaTheta > 0 { deltaTheta -= 2 * .pi }
    if sweep, deltaTheta < 0 { deltaTheta += 2 * .pi }

    // 每段不超過 90°,誤差小到看不出來
    let segments = Int(ceil(abs(deltaTheta) / (.pi / 2)))
    let step = deltaTheta / CGFloat(segments)
    let handle = 4 / 3 * tan(step / 4)
    func pointAndTangent(_ t: CGFloat) -> (CGPoint, CGVector) {
        let point = CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                            y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        let tangent = CGVector(dx: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                               dy: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        return (point, tangent)
    }
    for i in 0..<segments {
        let (start, startTangent) = pointAndTangent(theta1 + CGFloat(i) * step)
        let (end, endTangent) = pointAndTangent(theta1 + CGFloat(i + 1) * step)
        path.addCurve(
            to: i == segments - 1 ? p1 : end,
            control1: CGPoint(x: start.x + handle * startTangent.dx, y: start.y + handle * startTangent.dy),
            control2: CGPoint(x: end.x - handle * endTangent.dx, y: end.y - handle * endTangent.dy))
    }
}

// MARK: - 外框化與輸出

/// lucide 的 24×24 格線中心(12, 12)對到畫布中心，並放大 `unit` 倍。
var toCanvas = CGAffineTransform(translationX: canvas / 2, y: canvas / 2)
    .scaledBy(x: unit, y: unit)
    .translatedBy(x: -12, y: -12)

/// 把 stroke 轉成填色外框。`filled` 為 true 時連 path 內部一起填滿。
func outline(_ data: String, filled: Bool) -> CGPath {
    var parser = PathDataParser(data)
    let centerline = parser.parse()
    let stroked = centerline.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let shape = filled ? stroked.union(centerline, using: .winding) : stroked.normalized(using: .winding)
    return shape.copy(using: &toCanvas)!
}

func svgPathData(_ path: CGPath) -> String {
    func f(_ value: CGFloat) -> String {
        var text = String(format: "%.2f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
    var data = ""
    path.applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            data += "M\(f(p[0].x)) \(f(p[0].y))"
        case .addLineToPoint:
            data += "L\(f(p[0].x)) \(f(p[0].y))"
        case .addQuadCurveToPoint:
            data += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
        case .addCurveToPoint:
            data += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
        case .closeSubpath:
            data += "Z"
        @unknown default:
            fatalError("未知的 CGPath element")
        }
    }
    return data
}

func writeLayer(_ fileName: String, _ path: CGPath, note: String) throws {
    let size = Int(canvas)
    let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)">
          <!-- \(note)。由 tools/build-layers.swift 產生，請勿手動修改。
               源自 lucide book-heart(ISC License,Copyright (c) 2026 Lucide Icons and Contributors)。 -->
          <path fill="#FFFFFF" d="\(svgPathData(path))"/>
        </svg>

        """
    let url = assetsDir.appendingPathComponent(fileName)
    try svg.write(to: url, atomically: true, encoding: .utf8)
    let box = path.boundingBoxOfPath
    print("\(fileName): x \(Int(box.minX.rounded()))–\(Int(box.maxX.rounded())), y \(Int(box.minY.rounded()))–\(Int(box.maxY.rounded())) px")
}

let paths = try lucidePaths()
try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
// 檔名依 Icon Composer 文件的建議，由後往前編號
try writeLayer("1-book.svg", outline(paths[0], filled: false), note: "書(後層)")
try writeLayer("2-heart.svg", outline(paths[1], filled: true), note: "愛心(前層，實心)")
