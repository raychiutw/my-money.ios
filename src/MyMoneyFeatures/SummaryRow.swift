import MyMoneyDomain
import SwiftUI

/// 統計卡的一列：標題、金額、說明。
struct SummaryRow: View {
    let title: String
    let amount: Money
    let detail: String
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
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(amount.spokenText),\(detail)")
    }
}
