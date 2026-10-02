import MyMoneyFeatures
import Testing

@Suite("頭像配色:字與底色的對比(DESIGN.md「導覽」,#106)")
struct AvatarPaletteTests {
    @Test("淺色、深色的字與底色對比至少 7:1(WCAG AAA)", arguments: [AvatarPalette.Style.light, .dark])
    func standardStylesMeetSevenToOne(style: AvatarPalette.Style) {
        let ratio = AvatarPalette.palette(for: style).contrastRatio

        #expect(ratio >= 7, "\(style) 的對比只有 \(ratio):1")
    }

    @Test("增強對比時的對比更高，至少 10:1", arguments: [AvatarPalette.Style.lightIncreasedContrast, .darkIncreasedContrast])
    func increasedContrastStylesAreHigher(style: AvatarPalette.Style) {
        let ratio = AvatarPalette.palette(for: style).contrastRatio

        #expect(ratio >= 10, "\(style) 的對比只有 \(ratio):1")
    }

    @Test("增強對比的對比不低於同一種外觀的標準版", arguments: [
        (AvatarPalette.Style.light, AvatarPalette.Style.lightIncreasedContrast),
        (.dark, .darkIncreasedContrast),
    ])
    func increasedIsNotLowerThanStandard(standard: AvatarPalette.Style, increased: AvatarPalette.Style) {
        #expect(AvatarPalette.palette(for: increased).contrastRatio >= AvatarPalette.palette(for: standard).contrastRatio)
    }

    @Test("淺色與深色用同一組粉底黑字(使用者要求，品牌識別一致)")
    func lightAndDarkShareThePinkPalette() {
        #expect(AvatarPalette.palette(for: .light) == AvatarPalette.palette(for: .dark))
        #expect(AvatarPalette.palette(for: .lightIncreasedContrast) == AvatarPalette.palette(for: .darkIncreasedContrast))
        let light = AvatarPalette.palette(for: .light)
        #expect(light.fill == AvatarPalette.RGB(red: 255, green: 156, blue: 156))
        #expect(light.letter == AvatarPalette.RGB(red: 31, green: 5, blue: 7))
    }

    @Test("WCAG 對比公式:黑底白字是 21:1,同色是 1:1")
    func contrastFormula() {
        let black = AvatarPalette.RGB(red: 0, green: 0, blue: 0)
        let white = AvatarPalette.RGB(red: 255, green: 255, blue: 255)

        #expect(AvatarPalette(fill: black, letter: white).contrastRatio == 21)
        #expect(AvatarPalette(fill: white, letter: white).contrastRatio == 1)
    }
}
