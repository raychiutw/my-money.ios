import MyMoneyFeatures
import Testing

/// 套用中的篩選圖示(#147):沒套用是一般的三條線，套用中是三條線加空心圓圈(顏色是品牌粉紅,由 UI 測試用像素驗證)。
/// 以前套用中是實心圓,在玻璃 toolbar 上變成一顆反白填滿的圓,不符合「按鈕一律不填色」。
@Suite("篩選按鈕的圖示")
struct FilterIconTests {
    @Test("沒套用篩選：三條線;套用中：三條線加空心圓圈，不是實心")
    func symbolNames() {
        #expect(FilterIcon.symbolName(isActive: false) == "line.3.horizontal.decrease")
        #expect(FilterIcon.symbolName(isActive: true) == "line.3.horizontal.decrease.circle")
        #expect(!FilterIcon.symbolName(isActive: true).hasSuffix(".fill"), "套用中的篩選又變成實心圓")
    }
}
