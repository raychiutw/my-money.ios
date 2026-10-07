import MyMoneyDomain
import SwiftUI

/// 超支提示(#117):沒有超支時完全不出現;有超支時是一個精簡的紅色圓角提示，點了切到統計 tab 的預算額度。
struct OverBudgetChip: View {
    let title: String
    let spokenTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // 不用膠囊:大字級文字折成多行時，膠囊的兩端會切到文字。
                .background(.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(spokenTitle)
        .accessibilityHint("查看預算額度")
    }
}

/// 功能入口的一格(#178):圖示、名稱加一個關鍵數字;整格是一個按鈕。
/// 放在 `OverviewEntryGrid` 裡:最多兩欄,名稱放得下才並排,否則單欄(無障礙字級),單欄時關鍵數字在最下面靠右。
/// 關鍵數字不影響欄數(理想寬度算 0,放不下就折行,不截斷);沒有數字(還沒載入或載入失敗)時只有圖示和名稱。
struct OverviewEntryCard: View {
    let title: String
    let symbolName: String
    let value: String?
    var isWarning = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let value {
                    BreakableLine(text: value, alignment: valueAlignment)
                        .font(.subheadline)
                        .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        // 理想寬度 0:數字長短不改變欄數;放不下就換行。
                        .frame(idealWidth: 0, maxWidth: .infinity, alignment: frameAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private var valueAlignment: HorizontalAlignment {
        dynamicTypeSize.isAccessibilitySize ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        dynamicTypeSize.isAccessibilitySize ? .trailing : .leading
    }
}

/// 入口格(#178):跟帳戶卡片網格同一套欄數規則(`TileColumns`),最多兩欄。
struct OverviewEntryGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualColumnsLayout(maxColumns: 2, spacing: 10, rowSpacing: 10) {
                content()
            }
            VStack(spacing: 10) {
                content()
            }
        }
    }
}

/// 總覽「接下來 60 天」的一列預定收支(#189):名稱、次要文字「日期・歸屬」、帶正負號的金額(收入綠、支出紅),
/// 右邊是「已繳」圓圈(沒有識別碼或不能勾選的事件沒有圓圈)。已繳的整列變淡、金額加刪除線,次要文字寫「已繳」(不只靠顏色)。
/// 無障礙字級左右放不下,改成名稱、次要文字、金額由上往下,金額在最下面靠右,圓圈在最右邊。
struct UpcomingEventRow: View {
    let row: UpcomingEvent
    let isBusy: Bool
    let toggle: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            texts
                .opacity(row.event.isSettled ? 0.58 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spokenText)
            if row.isSettleable {
                SettleButton(isSettled: row.event.isSettled, isBusy: isBusy, action: toggle)
                    .accessibilityLabel(row.checkLabel)
                    .accessibilityIdentifier("overview.settle.\(row.id)")
            }
        }
    }

    @ViewBuilder
    private var texts: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                subtitle
                amount.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    name
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                amount
            }
        }
    }

    private var name: some View {
        Text(row.event.name)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
    }

    private var subtitle: some View {
        BreakableLine(text: "\(row.dateText)・\(row.subtitle)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// 金額一律單行。
    private var amount: some View {
        Text(row.amountText)
            .monospacedDigit()
            .foregroundStyle(row.event.amount.tone(of: row.isIncome ? .inflow : .outflow).color ?? .primary)
            .strikethrough(row.event.isSettled)
            .lineLimit(1)
            .fixedSize()
    }
}

/// 總覽帳戶卡(#190):橫向捲動的一排裡的一張。類型圖示(帳戶代表色)加名稱、大金額(靠右)、底下小字(信用卡兩行,現金與活存帳戶一行歸屬)。
/// 一般字級固定寬度(跟著字級放大);無障礙字級接近整個畫面寬,名稱完整折行、不截斷。點了看該帳戶的記帳。
struct OverviewAccountCardView: View {
    let card: OverviewAccountCard

    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 176
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(card.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // 名稱完整折行、不截斷(HIG 盡量少截斷);一般字級最多兩行。
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            } icon: {
                Image(systemName: card.symbolName)
                    .foregroundStyle(Color(hex: card.colorHex) ?? .gray)
            }
            Text(card.amountText)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(card.tone.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(card.detailLines, id: \.self) { line in
                BreakableLine(text: line, alignment: .leading)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .modifier(CardWidth(accessibility: dynamicTypeSize.isAccessibilitySize, width: cardWidth))
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private struct CardWidth: ViewModifier {
        let accessibility: Bool
        let width: CGFloat

        func body(content: Content) -> some View {
            if accessibility {
                // 無障礙字級:幾乎整個畫面寬,旁邊露出下一張的邊緣提示可以橫向捲動。
                content.containerRelativeFrame(.horizontal) { container, _ in container * 0.88 }
            } else {
                content.frame(width: width, alignment: .topLeading)
            }
        }
    }
}

/// 橫向捲動的一排帳戶卡(#190):每張一樣高,卡片可以捲到畫面邊緣之外(列表左右邊界不裁切)。
struct OverviewAccountCardRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                content()
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// 一行「甲・乙」放得下就一行;放不下就在「・」拆成上下兩行,不在字中間折斷(中文沒有空格,Text 會在任何字之間折行,
/// 「10月11日」可能被折成「10月」「11日」)。拆開之後每一段放不下仍會自己折行,不截斷。
struct BreakableLine: View {
    let text: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .lineLimit(1)
            VStack(alignment: alignment, spacing: 0) {
                ForEach(Array(text.components(separatedBy: "・").enumerated()), id: \.offset) { _, part in
                    Text(part)
                }
            }
        }
    }
}
