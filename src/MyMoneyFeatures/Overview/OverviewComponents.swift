import MyMoneyDomain
import SwiftUI

/// 總覽最近交易的一列(#117):只有分類圖示、名稱(備註，沒有備註時是分類)和帶正負號的金額。
/// 日期、帳戶、記帳人、歸屬在交易頁看。VoiceOver 念「分類，備註，收支金額」。
struct CompactTransactionRow: View {
    let transaction: MyMoneyDomain.Transaction

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.symbolName)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
            Text(transaction.displayTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 金額一律單行(DESIGN.md「列與欄位」)。
            Text(transaction.signedAmountText)
                .monospacedDigit()
                .foregroundStyle(transaction.amountColor)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// 例如「餐飲，午餐，支出 120 元」;沒有備註時不重複念分類。
    private var spokenText: String {
        var parts = [transaction.category.name]
        if !transaction.note.isEmpty { parts.append(transaction.note) }
        parts.append(transaction.spokenAmount)
        return parts.joined(separator: "，")
    }
}

/// 儲蓄目標的小圓環(#117):環中是達成百分比，旁邊是目標名稱。百分比來自後端的已存與目標金額;
/// 達成時用成功色(parity 刻意偏離第 6 項)。VoiceOver 念「名稱，已達成百分之 N」。
struct GoalRingRow: View {
    let goal: SavingsGoal

    /// 圓環跟環中的字(`footnote`)同一個文字樣式放大，字照系統大小、不用縮小就放得進環裡(#156)。
    @ScaledMetric(relativeTo: .footnote) private var ringSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            ring
            Text("\(goal.emoji) \(goal.name)")
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.ringSpokenText)
    }

    private var ring: some View {
        let color: Color = goal.isAchieved ? .green : .accentColor
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: goal.progress)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(goal.percentText)
                .font(.footnote.bold())
                .monospacedDigit()
                .lineLimit(1)
                .padding(8)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

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
