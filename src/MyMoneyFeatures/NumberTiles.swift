import MyMoneyDomain
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// 群組列表上一張卡片的底色，跟列表列的底色相同(深色模式也跟著系統)。
    static var groupedCardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

/// 大數字(#116、#118、#124):全 app 唯一放大的字級(DESIGN.md「字型與數字」)。小標題加 88pt 的粗體金額，
/// 開頭的符號與貨幣(「$」「-$」)縮小成灰色，數字本身最大(設計稿);`@ScaledMetric` 跟著 Dynamic Type 放大，
/// 單行，放不下時縮小，不折行也不截斷。整塊是一個 VoiceOver 元素:標籤是標題，值是金額。
struct BigNumber: View {
    let title: String
    let amount: Money
    /// 顯示的文字，預設是金額。
    var text: String?
    /// 負數用紅色。
    var warnsWhenNegative = true

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            number
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .foregroundStyle(warnsWhenNegative && amount < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(amount.spokenText)
    }

    /// 開頭的符號與貨幣(第一個數字之前，例如「$」「-$」)是小的灰字，數字本身是大字。
    private var number: Text {
        let full = text ?? amount.formatted()
        let digitsStart = full.firstIndex(where: \.isNumber) ?? full.startIndex
        let symbol = Text(String(full[..<digitsStart]))
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.secondary)
        let digits = Text(String(full[digitsStart...]))
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .tracking(-size * 0.02)
        // `Text + Text` 在 iOS 26 已棄用:改用 Text 的字串插值組合不同字級的片段。
        return Text("\(symbol)\(digits)")
    }
}

/// 數字磚的排法：並排時標籤在上、數字在下;單欄時一格一列。由 `NumberTileRow` 依實際空間決定(#148)。
enum NumberTileStyle {
    /// 多欄並排：標籤在上、數字靠底。
    case column
    /// 單欄：標籤靠左、金額在右同一行;同一行放不下(無障礙字級)時標籤在上、金額在下一行。
    case row
}

private struct NumberTileStyleKey: EnvironmentKey {
    static let defaultValue = NumberTileStyle.column
}

extension EnvironmentValues {
    var numberTileStyle: NumberTileStyle {
        get { self[NumberTileStyleKey.self] }
        set { self[NumberTileStyleKey.self] = newValue }
    }
}

/// 數字磚(#117):小標籤加一個大數字，各 tab 摘要共用(DESIGN.md「數字磚與卡片」)。
/// 放在 `NumberTileRow` 裡，每格的理想寬度放得下就並排，放不下整排改單欄。
///
/// 數字單行，不折行、不截斷、不縮小(單欄時有整列的寬度)。VoiceOver 念「標籤，金額」。
struct NumberTile: View {
    let title: String
    let amount: Money
    /// 顯示的文字，預設是金額;帶正負號的總收入、總支出另外傳。
    var text: String?
    /// 數字的顏色，預設是主要文字色;`warnsWhenNegative` 時負數用紅色。
    var style: Color?
    var warnsWhenNegative = false
    /// VoiceOver 念的標籤，預設跟畫面上的標題一樣;畫面上用簡稱時，這裡用 CONTEXT.md 的正名(例如「信用卡待繳總額」)。
    var spokenTitle: String?

    @Environment(\.numberTileStyle) private var layoutStyle

    var body: some View {
        content
            .padding(12)
            .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTitle ?? title)
            .accessibilityValue(amount.spokenText)
    }

    @ViewBuilder
    private var content: some View {
        switch layoutStyle {
        case .column:
            VStack(alignment: .leading, spacing: 4) {
                label
                // 數字靠底、靠右:標籤一行或兩行的磚，數字還是在同一條線上(#149:金額一律靠右)。
                Spacer(minLength: 0)
                number
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .row:
            // 一格一列：標籤靠左、金額靠右在同一行;同一行放不下(無障礙字級)就標籤在上、金額在下一行。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    number
                }
                VStack(alignment: .leading, spacing: 4) {
                    label
                    number
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var label: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var number: some View {
        Text(text ?? amount.formatted())
            .font(.title3.bold())
            .monospacedDigit()
            .lineLimit(1)
            // 理想寬度不受縮小影響(欄數照原尺寸判斷);這只是最後的安全網，放不下時縮小也不要切到。
            .minimumScaleFactor(0.5)
            .foregroundStyle(color)
    }

    private var color: Color {
        if let style { return style }
        return warnsWhenNegative && amount < .zero ? .red : .primary
    }
}

/// 一排數字磚(#148):每一格的理想寬度(標籤單行、金額原尺寸，加內距)都放得進「可用寬度除以欄數」才並排，
/// 否則整排改單欄(一格一列)。只看實際可用的寬度，不看裝置或字級屬性(#117)。欄數的判斷見 `TileColumns`。
struct NumberTileRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // `ViewThatFits` 取第一個理想寬度放得下的：並排的理想寬度就是 `TileColumns.requiredWidth`。
        ViewThatFits(in: .horizontal) {
            EqualColumnsLayout(maxColumns: 3, spacing: 8, rowSpacing: 8) {
                content()
            }
            .environment(\.numberTileStyle, .column)
            VStack(spacing: 8) {
                content()
            }
            .environment(\.numberTileStyle, .row)
        }
    }
}

/// 等寬的欄：欄數由 `TileColumns` 決定(格子的理想寬度放得下才多欄，否則單欄);每一排的格子一樣高。
/// 沒有限定寬度時回報「照理想欄數並排需要的寬度」，`ViewThatFits` 靠它判斷放不放得下。
struct EqualColumnsLayout: Layout {
    let maxColumns: Int
    let spacing: CGFloat
    let rowSpacing: CGFloat

    private func idealWidths(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }

    private struct Arrangement {
        let columns: Int
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        let ideals = idealWidths(subviews)
        let columns = TileColumns.count(idealWidths: ideals, availableWidth: width, spacing: spacing, maxColumns: maxColumns)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let heights = stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(.init(width: columnWidth, height: nil)).height }.max() ?? 0
        }
        return Arrangement(columns: columns, columnWidth: columnWidth, rowHeights: heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? TileColumns.requiredWidth(
            idealWidths: idealWidths(subviews), spacing: spacing, columns: min(maxColumns, subviews.count)
        )
        let layout = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.rowHeights.reduce(0, +) + rowSpacing * CGFloat(layout.rowHeights.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let layout = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in layout.rowHeights.enumerated() {
            for column in 0..<layout.columns {
                let index = row * layout.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + (layout.columnWidth + spacing) * CGFloat(column)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .init(width: layout.columnWidth, height: height)
                )
            }
            y += height + rowSpacing
        }
    }
}

/// 帳戶卡片(#117、#149):第一行圖示加名稱;第二行左邊是選填的小字(歸屬、信用卡的「N 日繳」)，右邊是金額，**金額靠右**單行。
/// 放在 `NumberCardGrid` 裡，同一排的卡片一樣高。同一行放不下(無障礙字級)時上下堆疊:小字在上、**金額在最下面一行靠右**。
struct NumberCard: View {
    let title: String
    let symbol: String
    let symbolColor: Color
    let amount: Money
    /// 警示狀態(例如信用卡有待繳):金額用紅色。
    var isWarning = false
    /// 金額同一行左邊的小字，例如「個人私帳・5 日繳」;沒有就只有金額。
    var caption: String?
    /// VoiceOver 念的整句。
    let spokenText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(symbolColor)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    captionText
                    Spacer(minLength: 4)
                    amountText
                }
                VStack(alignment: .leading, spacing: 4) {
                    captionText
                    amountText
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    @ViewBuilder
    private var captionText: some View {
        if let caption {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var amountText: some View {
        Text(amount.formatted())
            .font(.title3.bold())
            .monospacedDigit()
            .lineLimit(1)
            // 理想寬度不受縮小影響;只是最後的安全網。
            .minimumScaleFactor(0.6)
            .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }
}

/// 卡片網格(#148):最多兩欄，每一張的理想寬度(名稱單行、金額原尺寸，加內距)都放得進「可用寬度除以欄數」才並排，
/// 否則整個網格改單欄;每一排的卡片一樣高。卡片不多(總覽最多 6 張)，所以不用 `LazyVGrid`。欄數的判斷見 `TileColumns`。
struct NumberCardGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualColumnsLayout(maxColumns: 2, spacing: 12, rowSpacing: 12) {
                content()
            }
            VStack(spacing: 12) {
                content()
            }
        }
    }
}
