import CoreGraphics
import MyMoneyFeatures
import Testing

@Suite("iPad 可讀寬度的左右邊界(#173)")
struct ReadableWidthTests {
    @Test("視窗比最大寬度窄或剛好:邊界是 0,iPhone 與 Split View 的版面不變", arguments: [320, 390, 430, 700] as [CGFloat])
    func narrowWindowsHaveNoMargin(width: CGFloat) {
        #expect(ReadableWidth.margin(forWidth: width) == 0)
    }

    @Test("視窗比最大寬度寬:超出的部分平均分到左右兩側", arguments: [(820, 60), (1024, 162), (1366, 333)] as [(CGFloat, CGFloat)])
    func wideWindowsSplitTheExcess(width: CGFloat, margin: CGFloat) {
        #expect(ReadableWidth.margin(forWidth: width) == margin)
        #expect(width - 2 * margin == ReadableWidth.maxWidth, "內容寬度剛好是最大寬度")
    }

    @Test("還沒量到寬度(0)時沒有邊界")
    func unmeasured() {
        #expect(ReadableWidth.margin(forWidth: 0) == 0)
    }
}
