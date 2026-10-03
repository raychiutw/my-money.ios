import CoreGraphics
import MyMoneyFeatures
import Testing

/// 摘要磚與帳戶卡片網格該排幾欄(#148):每一格的理想寬度(標籤單行寬度與金額原尺寸寬度中較大者加內距)
/// 放得進「可用寬度除以欄數」才並排;只要有任何一格放不下，整排改單欄。取代 #127、#124 的「最小寬度 92pt 隨字級放大」。
@Suite("數字磚與卡片的欄數")
struct TileColumnsTests {
    private let spacing: CGFloat = 8

    @Test("三格都放得下：三欄並排")
    func allFit() {
        // 可用 358:(358 - 16) / 3 = 114,最寬那格 110。
        #expect(TileColumns.count(idealWidths: [100, 110, 90], availableWidth: 358, spacing: spacing, maxColumns: 3) == 3)
    }

    @Test("剛好放得下(相等)也並排")
    func exactFit() {
        #expect(TileColumns.count(idealWidths: [114, 100, 100], availableWidth: 358, spacing: spacing, maxColumns: 3) == 3)
    }

    @Test("只有一格放不下：整排改單欄，不是只有那一格")
    func oneCellTooWide() {
        #expect(TileColumns.count(idealWidths: [100, 115, 90], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
    }

    @Test("金額太寬(理想寬度被金額撐大)：單欄")
    func wideAmount() {
        // 標籤很短，但金額 $1,234,567 原尺寸要 130。
        #expect(TileColumns.count(idealWidths: [60, 130, 60], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
        // 最寬的是第一格或最後一格也一樣:每一格都要看,不能漏掉。
        #expect(TileColumns.count(idealWidths: [130, 60, 60], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
        #expect(TileColumns.count(idealWidths: [60, 60, 130], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
    }

    @Test("可用寬度很小(窄螢幕或分割視窗)：單欄")
    func narrow() {
        #expect(TileColumns.count(idealWidths: [100, 100, 100], availableWidth: 250, spacing: spacing, maxColumns: 3) == 1)
    }

    @Test("只有一格或沒有格子：單欄")
    func singleOrEmpty() {
        #expect(TileColumns.count(idealWidths: [100], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
        #expect(TileColumns.count(idealWidths: [], availableWidth: 358, spacing: spacing, maxColumns: 3) == 1)
    }

    @Test("帳戶卡片網格最多兩欄:卡片比欄數多也一樣判斷")
    func cardGrid() {
        // 可用 361,間距 12:(361 - 12) / 2 = 174.5。
        #expect(TileColumns.count(idealWidths: [150, 170, 160, 120], availableWidth: 361, spacing: 12, maxColumns: 2) == 2)
        #expect(TileColumns.count(idealWidths: [150, 176, 160, 120], availableWidth: 361, spacing: 12, maxColumns: 2) == 1)
    }

    @Test("格子比最多欄數少時，欄數就是格子數")
    func fewerCellsThanMaximum() {
        #expect(TileColumns.count(idealWidths: [100, 100], availableWidth: 358, spacing: spacing, maxColumns: 3) == 2)
    }

    @Test("n 欄並排需要的寬度：最寬那格乘欄數加間距")
    func requiredWidth() {
        #expect(TileColumns.requiredWidth(idealWidths: [100, 110, 90], spacing: spacing, columns: 3) == CGFloat(346))
        #expect(TileColumns.requiredWidth(idealWidths: [100, 110, 90], spacing: spacing, columns: 1) == CGFloat(110))
        #expect(TileColumns.requiredWidth(idealWidths: [], spacing: spacing, columns: 3) == CGFloat(0))
    }
}
