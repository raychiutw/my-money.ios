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

/// 大數字(#116、#118、#124、#156):全 app 唯一放大的字級(DESIGN.md「字型與數字」)，用 HIG 最大的文字樣式 Large Title(粗體)，
/// 開頭的符號與貨幣(「$」「-$」)是下一級的 Title(半粗、灰色)，數字本身最大。
/// 只用文字樣式、不寫死 pt 值，完全照系統字級放大縮小;單行，放不下時**不縮小**,改用 Title 樣式的整行(仍是文字樣式)。
/// 整塊是一個 VoiceOver 元素:標籤是標題，值是金額。
struct BigNumber: View {
    let title: String
    let amount: Money
    /// 顯示的文字，預設是金額。
    var text: String?
    /// 負數用紅色。
    var warnsWhenNegative = true
    /// 指定顏色(#202:流量的淨額正數綠、負數紅);沒有指定時照 `warnsWhenNegative`。
    var style: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // 放不下(極大字級加很長的金額)時整行降一級，不是縮小。
            ViewThatFits(in: .horizontal) {
                number(digits: .largeTitle.weight(.bold), symbol: .title.weight(.semibold))
                number(digits: .title.weight(.bold), symbol: .title3.weight(.semibold))
            }
            .lineLimit(1)
            .foregroundStyle(
                style.map(AnyShapeStyle.init) ?? (warnsWhenNegative && amount < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(amount.spokenText)
    }

    /// 開頭的符號與貨幣(第一個數字之前，例如「$」「-$」)是小的灰字，數字本身是大字。
    private func number(digits digitsFont: Font, symbol symbolFont: Font) -> Text {
        let full = text ?? amount.formatted()
        let digitsStart = full.firstIndex(where: \.isNumber) ?? full.startIndex
        let symbol = Text(String(full[..<digitsStart]))
            .font(symbolFont)
            .foregroundStyle(.secondary)
        let digits = Text(String(full[digitsStart...]))
            .font(digitsFont)
            .monospacedDigit()
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
    /// 金額底下的組成明細(總覽的三格數字,#178):小字、靠右、放不下就折行(不截斷)。
    var details: [String] = []
    /// 明細的 VoiceOver 念法;沒有時念畫面上的字。
    var spokenDetails: String?

    @Environment(\.numberTileStyle) private var layoutStyle

    var body: some View {
        content
            .padding(12)
            .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenTitle ?? title)
            .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        let details = spokenDetails ?? self.details.joined(separator: "，")
        return details.isEmpty ? amount.spokenText : "\(amount.spokenText)，\(details)"
    }

    /// 明細不影響欄數:理想寬度算 0(放不下就折行),所以磚是否並排只看標籤與金額。
    @ViewBuilder
    private var detailLines: some View {
        if !details.isEmpty {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(idealWidth: 0, maxWidth: .infinity, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
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
                detailLines
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .row:
            // 一格一列：標籤靠左、金額靠右在同一行;同一行放不下(無障礙字級)就標籤在上、金額在下一行。明細在金額底下。
            VStack(alignment: .leading, spacing: 4) {
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
                detailLines
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
    /// 骨架屏用:直接指定單欄或並排(來自上一次載入完成時記下的排法,#201);`nil` 是由空間決定。
    var forcedSingleColumn: Bool?
    /// 載入完成後的真實畫面用:把實際選到的排法記下來給骨架屏參考。
    var memory: SkeletonShapeMemory?
    @ViewBuilder var content: () -> Content

    var body: some View {
        AdaptiveColumns(
            maxColumns: 3, spacing: 8, memory: memory, key: "tiles", forcedSingleColumn: forcedSingleColumn
        ) { isSingleColumn in
            content()
                .environment(\.numberTileStyle, isSingleColumn ? .row : .column)
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
    /// 顯示的文字,預設是金額;信用卡待繳是負數(#202)另外傳。
    var text: String?
    /// 警示狀態(例如信用卡有待繳):金額用紅色。
    var isWarning = false
    /// 金額同一行左邊的小字，例如「個人私帳・5 日繳」;沒有就只有金額。
    var caption: String?
    /// VoiceOver 念的整句。
    let spokenText: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // 無障礙字級有的是縱向空間:名稱完整折行、不截斷(HIG 盡量少截斷);其他字級最多兩行。
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
        Text(text ?? amount.formatted())
            .font(.title3.bold())
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }
}

/// 卡片網格(#148):最多兩欄，每一張的理想寬度(名稱單行、金額原尺寸，加內距)都放得進「可用寬度除以欄數」才並排，
/// 否則整個網格改單欄;每一排的卡片一樣高。卡片不多(總覽最多 6 張)，所以不用 `LazyVGrid`。欄數的判斷見 `TileColumns`。
struct NumberCardGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        AdaptiveColumns(maxColumns: 2, spacing: 12) { _ in content() }
    }
}
