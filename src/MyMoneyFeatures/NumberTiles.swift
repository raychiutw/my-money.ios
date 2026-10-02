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

/// 數字磚(#117):小標籤加一個大數字，各 tab 摘要共用(DESIGN.md「數字磚與卡片」)。
/// 放在 `NumberTileRow` 裡，一排放得下就並排，放不下就上下堆疊。
///
/// 數字單行，磚太窄時縮小，不折行、不截斷。VoiceOver 念「標籤，金額」。
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            // 數字靠底:標籤一行或兩行的磚，數字還是在同一條線上。
            Spacer(minLength: 0)
            Text(text ?? amount.formatted())
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTitle ?? title)
        .accessibilityValue(amount.spokenText)
    }

    private var color: Color {
        if let style { return style }
        return warnsWhenNegative && amount < .zero ? .red : .primary
    }
}

/// 一排數字磚:每格至少要有 `minimumTileWidth`(跟著字級變大)，放得下就並排、等寬等高，放不下就上下堆疊。
/// 只看實際可用的寬度，不看裝置或字級屬性(#117)。
struct NumberTileRow<Content: View>: View {
    /// 設計稿是三格橫排:預設到 XXL 都並排(標籤單行、數字單行縮小)，XXXL 以上與無障礙字級才上下堆疊(#124、#127)。
    /// 最小寬度連同標籤的字級一起放大:XXL 時每格約 110pt(比 393pt 寬的 iPhone 每格 115pt 放得下)、XXXL 約 120pt(放不下才堆疊);
    /// 標籤「可支配現金」5 個字 90pt 放得進磚內(扣掉左右留白)。
    @ScaledMetric(relativeTo: .title3) private var minimumTileWidth: CGFloat = 92
    @ViewBuilder var content: () -> Content

    var body: some View {
        NumberTileLayout(minimumTileWidth: minimumTileWidth, spacing: 8) {
            content()
        }
    }
}

struct NumberTileLayout: Layout {
    let minimumTileWidth: CGFloat
    let spacing: CGFloat

    /// 寬度沒有限制時(ideal)並排。
    private func tileWidth(in width: CGFloat?, count: Int) -> CGFloat? {
        guard let width else { return nil }
        let candidate = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        return candidate >= minimumTileWidth ? candidate : nil
    }

    private func isSideBySide(_ width: CGFloat?, count: Int) -> Bool {
        width == nil || tileWidth(in: width, count: count) != nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = subviews.count
        guard count > 0 else { return .zero }
        if isSideBySide(proposal.width, count: count) {
            let width = tileWidth(in: proposal.width, count: count) ?? minimumTileWidth
            let height = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }.max() ?? 0
            return CGSize(width: proposal.width ?? (width * CGFloat(count) + spacing * CGFloat(count - 1)), height: height)
        }
        let width = proposal.width ?? minimumTileWidth
        let heights = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = subviews.count
        guard count > 0 else { return }
        if let width = tileWidth(in: bounds.width, count: count) {
            let height = bounds.height
            for (index, subview) in subviews.enumerated() {
                let origin = CGPoint(x: bounds.minX + (width + spacing) * CGFloat(index), y: bounds.minY)
                subview.place(at: origin, anchor: .topLeading, proposal: .init(width: width, height: height))
            }
        } else {
            var y = bounds.minY
            for subview in subviews {
                let height = subview.sizeThatFits(.init(width: bounds.width, height: nil)).height
                subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: .init(width: bounds.width, height: height))
                y += height + spacing
            }
        }
    }
}

/// 帳戶卡片(#117):圖示加名稱，下面是大金額，最下面是選填的小字(信用卡的「N 日繳」)。
/// 放在 `NumberCardGrid` 裡，同一排的卡片一樣高。
struct NumberCard: View {
    let title: String
    let symbol: String
    let symbolColor: Color
    let amount: Money
    /// 警示狀態(例如信用卡有待繳):金額用紅色。
    var isWarning = false
    var caption: String?
    /// 金額同一行右邊的小字(總覽信用卡的「5 日繳」，設計稿);放不下時金額先縮小。
    var trailingText: String?
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amount.formatted())
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                if let trailingText {
                    Spacer(minLength: 4)
                    Text(trailingText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }
}

/// 卡片網格:欄數由實際可用寬度決定(每欄至少 `minimumWidth`,跟著字級變大，大字級自然變一欄)，
/// 每一排的卡片一樣高。卡片不多(總覽最多 6 張)，所以不用 `LazyVGrid`。
struct NumberCardGrid<Content: View>: View {
    /// 設計稿是兩欄:到 XXL 都還是兩欄，更大的字級才變單欄(#124)。
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 136
    @ViewBuilder var content: () -> Content

    var body: some View {
        NumberCardGridLayout(minimumWidth: minimumWidth, spacing: 12) {
            content()
        }
    }
}

struct NumberCardGridLayout: Layout {
    let minimumWidth: CGFloat
    let spacing: CGFloat

    private func columns(in width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minimumWidth + spacing)))
    }

    /// 每一排的高度:那一排最高的卡片。
    private func rowHeights(width: CGFloat, subviews: Subviews) -> (columns: Int, columnWidth: CGFloat, heights: [CGFloat]) {
        let columns = columns(in: width)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let heights = stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(.init(width: columnWidth, height: nil)).height }.max() ?? 0
        }
        return (columns, columnWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? minimumWidth
        let layout = rowHeights(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.heights.reduce(0, +) + spacing * CGFloat(layout.heights.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let layout = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in layout.heights.enumerated() {
            for column in 0..<layout.columns {
                let index = row * layout.columns + column
                guard index < subviews.count else { break }
                let x = bounds.minX + (layout.columnWidth + spacing) * CGFloat(column)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .init(width: layout.columnWidth, height: height)
                )
            }
            y += height + spacing
        }
    }
}
