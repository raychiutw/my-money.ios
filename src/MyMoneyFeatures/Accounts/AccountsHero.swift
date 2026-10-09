import MyMoneyDomain
import SwiftUI

/// 帳戶頁最上面的主視覺(#119):超大的淨可用餘額(依帳戶檢視範圍，後端算好)，
/// 下面是現金、銀行存款、信用卡待繳的組成比例條與圖例。公式明細不寫(DESIGN.md「說明文字」)。
struct AccountsHero: View {
    let balance: Money
    let segments: [CompositionSegment]
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BigNumber(title: "淨可用餘額", amount: .stock(balance))
            if !segments.isEmpty {
                CompositionBar(segments: segments, summary: summary ?? "")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

/// 組成比例條:一條分段的長條，每段的長度是佔三項合計的比例;圖例用色點加文字，不只靠顏色。
struct CompositionBar: View {
    let segments: [CompositionSegment]
    let summary: String

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 12
    /// 圖例的色點跟著字級放大，大字級時才不會小到看不見。
    @ScaledMetric(relativeTo: .subheadline) private var dotSize: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// 每段的寬度是佔總寬(扣掉段與段的間隔)的比例;用 `GeometryReader` 取得總寬。
    private var bar: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(segments.count - 1, 0)) * 2
            let width = max(proxy.size.width - gaps, 0)
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.kind.color)
                        .frame(width: width * segment.fraction)
                }
            }
        }
        .frame(height: barHeight)
    }

    /// 色點加名稱和金額;放不下時折行(`ViewThatFits` 改成上下堆疊)。
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                ForEach(segments) { legendItem($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments) { legendItem($0) }
            }
        }
    }

    private func legendItem(_ segment: CompositionSegment) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(segment.kind.color)
                .frame(width: dotSize, height: dotSize)
            Text(segment.kind.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

extension CompositionSegment.Kind {
    /// 現金綠色、銀行存款藍色，信用卡待繳紅色(欠款的警示色，跟其他地方一致)。
    var color: Color {
        switch self {
        case .cash: .green
        case .bank: .blue
        case .cardDue: .red
        }
    }
}

/// ATM 提款／轉帳的膠囊按鈕(#119、#134):醒目的主要動作，在摘要下面;單色填滿的玻璃膠囊。
struct TransferCapsuleButton: View {
    let action: () -> Void

    var body: some View {
        PrimaryCapsuleButton(title: "ATM 提款／轉帳", systemImage: "arrow.left.arrow.right", fillsWidth: true, action: action)
            .accessibilityIdentifier("accounts.transfer")
    }
}
