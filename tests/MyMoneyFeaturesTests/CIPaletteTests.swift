import MyMoneyFeatures
import Testing

/// CI 色票(#175、ADR-0009):填色淺色與深色同一個，文字與線條分淺深兩個變體;對比用 WCAG 公式從實際色值算出。
@Suite("CI 色票:填色一致、文字與線條各自達標")
struct CIPaletteTests {
    private typealias RGB = AvatarPalette.RGB

    private static let white = RGB(red: 255, green: 255, blue: 255)
    private static let black = RGB(red: 0, green: 0, blue: 0)
    private static let groupedLight = RGB(red: 0xF2, green: 0xF2, blue: 0xF7)
    private static let card = RGB(red: 0x1C, green: 0x1C, blue: 0x1E)
    private static let secondaryCard = RGB(red: 0x2C, green: 0x2C, blue: 0x2E)

    /// 各外觀會放在哪些背景上。
    private static func backgrounds(for appearance: CIPalette.Appearance) -> [RGB] {
        switch appearance {
        case .light, .lightIncreasedContrast: [white, groupedLight]
        case .dark, .darkIncreasedContrast: [black, card, secondaryCard]
        }
    }

    private static func isIncreased(_ appearance: CIPalette.Appearance) -> Bool {
        appearance == .lightIncreasedContrast || appearance == .darkIncreasedContrast
    }

    @Test("填色上的勾勾與字至少 4:1(增強對比 7:1)", arguments: CIPalette.Appearance.allCases)
    func glyphOnFill(appearance: CIPalette.Appearance) {
        let ratio = CIPalette.fill(for: appearance).contrastRatio(with: CIPalette.glyph(for: appearance))

        #expect(ratio >= (Self.isIncreased(appearance) ? 7 : 4), "\(appearance):填色上的字只有 \(ratio):1")
    }

    @Test("填色在該外觀的每一種背景上至少 3:1(圖形元件)", arguments: CIPalette.Appearance.allCases)
    func fillAgainstBackgrounds(appearance: CIPalette.Appearance) {
        for background in Self.backgrounds(for: appearance) {
            let ratio = CIPalette.fill(for: appearance).contrastRatio(with: background)

            #expect(ratio >= 3, "\(appearance):填色對 \(background) 只有 \(ratio):1")
        }
    }

    @Test("文字與線條在該外觀的每一種背景上至少 4.5:1(增強對比 7:1)", arguments: CIPalette.Appearance.allCases)
    func textAgainstBackgrounds(appearance: CIPalette.Appearance) {
        for background in Self.backgrounds(for: appearance) {
            let ratio = CIPalette.text(for: appearance).contrastRatio(with: background)

            #expect(ratio >= (Self.isIncreased(appearance) ? 7 : 4.5), "\(appearance):文字對 \(background) 只有 \(ratio):1")
        }
    }

    @Test("填色淺色與深色是同一個顏色(品牌識別一致)")
    func fillIsTheSameInLightAndDark() {
        #expect(CIPalette.fill(for: .light) == CIPalette.fill(for: .dark))
        #expect(CIPalette.fill(for: .light) == RGB(red: 0xE2, green: 0x3C, blue: 0x52))
    }

    @Test("文字與線條的變體跟填色是同一個色相(紅偏粉，不是橘也不是紫)", arguments: CIPalette.Appearance.allCases)
    func textHueMatchesFill(appearance: CIPalette.Appearance) {
        let fill = CIPalette.fill(for: .light).hue
        let hue = CIPalette.text(for: appearance).hue
        let distance = min(abs(hue - fill), 360 - abs(hue - fill))

        #expect(distance <= 8, "\(appearance):文字色相 \(hue)° 離填色 \(fill)° 太遠")
    }

    @Test("WCAG 對比公式:黑底白字是 21:1")
    func contrastFormula() {
        #expect(Self.black.contrastRatio(with: Self.white) == 21)
        #expect(Self.white.contrastRatio(with: Self.white) == 1)
    }
}
