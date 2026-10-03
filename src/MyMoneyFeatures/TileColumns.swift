import CoreGraphics

/// 摘要磚與帳戶卡片網格該排幾欄(#148、DESIGN.md「數字磚與卡片」):純函式，不碰畫面，可以單獨測試。
///
/// 每一格有一個**理想寬度**:標籤單行的寬度與金額原尺寸的寬度中較大者，加上內距。
/// 放得進「可用寬度除以欄數」才並排;只要有任何一格放不下，**整排**改單欄(標籤不折行、金額不被縮小或切到)。
/// 取代 #127、#124 的「每格至少 92pt、隨字級放大、到 XXL 都並排」。
public enum TileColumns {
    /// 欄數：最多 `maxColumns` 欄(格子比它少時就是格子數)，放不下是 1。
    public static func count(idealWidths: [CGFloat], availableWidth: CGFloat, spacing: CGFloat, maxColumns: Int) -> Int {
        let columns = min(maxColumns, idealWidths.count)
        guard columns > 1, let widest = idealWidths.max() else { return 1 }
        let columnWidth = (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return widest <= columnWidth ? columns : 1
    }

    /// `columns` 欄並排需要的最小總寬度:最寬那格乘欄數，加欄與欄之間的間距。
    public static func requiredWidth(idealWidths: [CGFloat], spacing: CGFloat, columns: Int) -> CGFloat {
        guard let widest = idealWidths.max(), columns > 0 else { return 0 }
        return widest * CGFloat(columns) + spacing * CGFloat(columns - 1)
    }
}
