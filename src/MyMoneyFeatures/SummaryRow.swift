import MyMoneyDomain
import SwiftUI

/// 統計卡的一列：標題、金額，以及選填的明細(例如「N 個現金錢包」;解釋算法的說明不寫，見 DESIGN.md「說明文字」)。
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
