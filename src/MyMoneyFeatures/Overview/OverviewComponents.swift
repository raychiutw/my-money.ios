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
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(isWarning ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        // 理想寬度 0:數字長短不改變欄數;放不下就折行。
                        .frame(idealWidth: 0, maxWidth: .infinity, alignment: valueAlignment)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.groupedCardBackground, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private var valueAlignment: Alignment {
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
