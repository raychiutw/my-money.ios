import Foundation
import MyMoneyFeatures
import Testing

/// AccentColor 資產(#134、ADR-0007):互動元素用單色，不用品牌粉紅也不用系統藍。
/// 淺色黑、深色白，增強對比同;主要動作的字用反色(系統背景色)，對比用 WCAG 公式驗證。
@Suite("AccentColor:單色")
struct AccentColorTests {
    private struct Variant {
        let name: String
        let isDark: Bool
        let isHighContrast: Bool
        let rgb: AvatarPalette.RGB
    }

    private static let assetURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "src/App/MyMoney/Assets.xcassets/AccentColor.colorset/Contents.json")

    private func variants() throws -> [Variant] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.assetURL)) as? [String: Any]
        let colors = try #require(json?["colors"] as? [[String: Any]])
        return try colors.map { entry in
            let appearances = (entry["appearances"] as? [[String: String]]) ?? []
            let isDark = appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" }
            let isHighContrast = appearances.contains { $0["appearance"] == "contrast" && $0["value"] == "high" }
            let components = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
            func channel(_ key: String) throws -> Int {
                let text = try #require(components[key])
                if text.hasPrefix("0x") { return try #require(Int(text.dropFirst(2), radix: 16)) }
                return Int((try #require(Double(text)) * 255).rounded())
            }
            return Variant(
                name: "\(isDark ? "深色" : "淺色")\(isHighContrast ? "增強對比" : "")", isDark: isDark, isHighContrast: isHighContrast,
                rgb: AvatarPalette.RGB(red: try channel("red"), green: try channel("green"), blue: try channel("blue"))
            )
        }
    }

    @Test("四個變體(淺色、深色、各加增強對比)都在，而且都是單色:淺色黑、深色白")
    func fourMonochromeVariants() throws {
        let all = try variants()
        #expect(all.count == 4, "AccentColor 要有 4 個變體")
        #expect(Set(all.map(\.name)) == Set<String>(["淺色", "深色", "淺色增強對比", "深色增強對比"]))
        for variant in all {
            let expected = variant.isDark ? 255 : 0
            let channels: [Int] = [variant.rgb.red, variant.rgb.green, variant.rgb.blue]
            #expect(channels.allSatisfy { $0 == expected }, "\(variant.name):不是單色\(variant.isDark ? "白" : "黑")(\(channels))")
        }
    }

    @Test("主要動作:底色是 accent、字是反色(淺色白、深色黑)，對比至少 4.5:1(WCAG AA)")
    func primaryButtonTextContrast() throws {
        for variant in try variants() {
            let inverse = variant.isDark ? 0 : 255
            let text = AvatarPalette.RGB(red: inverse, green: inverse, blue: inverse)
            let ratio = AvatarPalette(fill: variant.rgb, letter: text).contrastRatio
            #expect(ratio >= 4.5, "\(variant.name):按鈕字與底色只有 \(ratio):1")
        }
    }

    @Test("accent 不是品牌粉紅也不是系統藍")
    func notBrandPinkNorSystemBlue() throws {
        for variant in try variants() {
            #expect(abs(variant.rgb.red - variant.rgb.blue) < 8, "\(variant.name):偏紅或偏藍")
        }
    }
}
