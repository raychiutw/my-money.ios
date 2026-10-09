import MyMoneyDomain
import SwiftUI

/// 摘要的主數字(DESIGN.md「列與欄位」第 6 條):標題和大字的金額。每頁最多一個，其餘數字用 `AmountRow`。
/// 明細選填(例如整體達成率);解釋算法的說明不寫，見 DESIGN.md「說明文字」。
struct SummaryRow: View {
    let title: String
    let amount: AmountPresentation
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(amount.text)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(amount.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
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
    let amount: AmountPresentation

    var body: some View {
        LabeledContent(title) {
            Text(amount.text)
                .foregroundStyle(amount.color ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(amount.spokenText)
    }
}

/// 一個金額的文字(#208):文字與顏色都來自 `AmountPresentation`,呼叫端不再自己配對。字級、行數等由呼叫端接著加。
struct AmountText: View {
    let amount: AmountPresentation

    init(_ amount: AmountPresentation) {
        self.amount = amount
    }

    var body: some View {
        Text(amount.text)
            .foregroundStyle(amount.color ?? .primary)
    }
}
