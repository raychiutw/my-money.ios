import SwiftUI

/// 「這一排放得下幾欄」(#208):放得下 `maxColumns` 欄就等寬並排,放不下整排改單欄。
///
/// 判斷、排版與骨架共用的記憶都在這裡:欄數的規則是 `TileColumns`(每一格的理想寬度放得進可用寬度除以欄數才並排);
/// 載入完成後的真實畫面把實際選到的排法記進 `memory`(連同寬度與字級),骨架屏下一次用 `forcedSingleColumn` 照它排,
/// 版面就不會在資料回來時從三欄跳成三排(#201、#204)。四個網格元件(數字磚、入口格、卡片網格…)共用同一個決定。
///
/// `content` 收到「現在是不是單欄」,讓呼叫端依排法調整每一格(例如數字磚的 `numberTileStyle`)。
struct AdaptiveColumns<Content: View>: View {
    let maxColumns: Int
    let spacing: CGFloat
    var rowSpacing: CGFloat?
    /// 載入完成後的真實畫面傳:把選到的排法記下來給骨架屏參考;骨架屏與沒有記憶需求的畫面不傳。
    var memory: SkeletonShapeMemory?
    /// 記憶的名稱(同一個畫面可以有數字磚與入口格兩個)。
    var key = "columns"
    /// 骨架屏用:直接指定單欄或並排(來自上一次記下的排法);`nil` 是由空間決定。
    var forcedSingleColumn: Bool?
    @ViewBuilder var content: (_ isSingleColumn: Bool) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: Double?
    @State private var chosenSingleColumn: Bool?

    var body: some View {
        arranged
            .onGeometryChange(for: Double.self) { $0.size.width } action: {
                width = $0
                flush()
            }
    }

    @ViewBuilder
    private var arranged: some View {
        if let forcedSingleColumn {
            if forcedSingleColumn { rows } else { columns }
        } else {
            // `ViewThatFits` 取第一個理想寬度放得下的:並排的理想寬度就是 `TileColumns.requiredWidth`。
            ViewThatFits(in: .horizontal) {
                columns
                    .onAppear { remember(isSingleColumn: false) }
                rows
                    .onAppear { remember(isSingleColumn: true) }
            }
        }
    }

    private var columns: some View {
        EqualColumnsLayout(maxColumns: maxColumns, spacing: spacing, rowSpacing: rowSpacing ?? spacing) {
            content(false)
        }
    }

    private var rows: some View {
        VStack(spacing: rowSpacing ?? spacing) {
            content(true)
        }
    }

    private func remember(isSingleColumn: Bool) {
        chosenSingleColumn = isSingleColumn
        flush()
    }

    /// 寬度與選到的排法都知道了才記(兩者到達的順序不一定)。
    private func flush() {
        guard let memory, let width, let chosenSingleColumn else { return }
        memory.recordArrangement(isSingleColumn: chosenSingleColumn, width: width, sizeKey: String(describing: dynamicTypeSize), for: key)
    }
}
