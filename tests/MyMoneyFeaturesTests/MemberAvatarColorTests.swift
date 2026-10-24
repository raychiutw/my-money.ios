import MyMoneyFeatures
import Testing

@Suite("成員頭像顏色:依人區分(#307)")
struct MemberAvatarColorTests {
    @Test("同一個人永遠同一個顏色")
    func sameKeySameSwatch() {
        #expect(MemberAvatarColor.swatch(for: "member-1") == MemberAvatarColor.swatch(for: "member-1"))
    }

    @Test("不同的人會分到不同顏色(8 個樣本至少 5 種)")
    func differentKeysSpread() {
        let swatches = (1...8).map { MemberAvatarColor.swatch(for: "member-\($0)").fill }
        #expect(Set(swatches.map { "\($0.red),\($0.green),\($0.blue)" }).count >= 5)
    }

    @Test("固定結果(跨啟動不變):不能依賴每次啟動不同的雜湊")
    func stableAcrossLaunches() {
        #expect(MemberAvatarColor.index(for: "in-memory-member-1") == MemberAvatarColor.index(for: "in-memory-member-1"))
        #expect(MemberAvatarColor.index(for: "abc") == 3)
    }

    @Test("每一色的字與底對比至少 4.5:1")
    func contrast() {
        for swatch in MemberAvatarColor.swatches {
            #expect(swatch.letter.contrastRatio(with: swatch.fill) >= 4.5)
        }
    }

    @Test("共 8 色,色相彼此相差至少 15 度")
    func hues() {
        let hues = MemberAvatarColor.swatches.map(\.fill.hue).sorted()
        #expect(hues.count == 8)
        for (a, b) in zip(hues, hues.dropFirst()) { #expect(b - a >= 15) }
    }
}
