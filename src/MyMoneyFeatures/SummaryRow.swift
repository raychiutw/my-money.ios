import MyMoneyDomain
import SwiftUI

/// 摘要的主數字(DESIGN.md「列與欄位」第 6 條):標題和大字的金額。每頁最多一個，其餘數字用 `AmountRow`。
/// 明細選填(例如整體達成率);解釋算法的說明不寫，見 DESIGN.md「說明文字」。
struct SummaryRow: View {
    let title: String
    let amount: Money
    var detail: String?
    var warnsWhenNegative = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(amount.formatted())
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(warnsWhenNegative && amount < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title) \(amount.spokenText),\($0)" } ?? "\(title) \(amount.spokenText)")
    }
}

/// 摘要的一般列(DESIGN.md「列與欄位」):標籤在左、金額在右，大字級放不下時 `LabeledContent` 自動改成上下堆疊;
/// 金額一律單行。VoiceOver 念標籤，值是金額。
struct AmountRow: View {
    let title: String
    let amount: Money
    /// 顯示的文字，預設是金額;交易頁的總收入、總支出另外帶正負號。
    var text: String?
    /// 金額的顏色，預設是主要文字色;`warnsWhenNegative` 時負數用紅色。
    var style: Color?
    var warnsWhenNegative = false

    var body: some View {
        LabeledContent(title) {
            Text(text ?? amount.formatted())
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(amount.spokenText)
    }

    private var color: Color {
        if let style { return style }
        return warnsWhenNegative && amount < .zero ? .red : .primary
    }
}
