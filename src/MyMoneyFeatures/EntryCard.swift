import SwiftUI

/// 明細卡(DESIGN.md「明細卡與輸入框」方案 B,#280):記帳頁、成員代墊明細、撥款沖帳紀錄、信用卡與帳戶詳細頁的收支明細共用。
///
/// - 前緣:分類圖示(沒有圖示就不留位置)。
/// - 標題:最多兩行(無障礙字級不限),長備註的全文看詳細頁。
/// - 標題下方:狀態膠囊(例如「家庭公帳・待報銷」);沒有狀態就沒有。
/// - 時間、記帳人、資產帳戶**各占一行、不連成一排**,每行前面一個小圖示(時鐘、人像、錢包),順序固定;沒有資料的整行不出現。
/// - 金額:固定在最右欄、單行、等寬數字,跟標題同一行;⋯ 另外並排在列的右邊(見 `reservingMoreMenuSpace`),所以有沒有 ⋯ 都不影響金額欄。
///
/// **結構只跟字級走、不跟資料長短走**(#248):無障礙字級上下堆疊——圖示加文字欄、金額最後一行靠右;其他字級一律兩欄。
/// 圖示只是裝飾,VoiceOver 由呼叫端用一句完整的話念(含收支方向)。
struct EntryCard: View {
    /// 小圖示加文字的一行。
    struct Line: Equatable {
        enum Kind: String { case time, recorder, account }
        let kind: Kind
        let text: String

        var symbolName: String {
            switch kind {
            case .time: "clock"
            case .recorder: "person"
            case .account: "wallet.bifold"
            }
        }
    }

    /// 前緣的分類圖示;沒有就不放。
    var symbolName: String?
    let title: String
    var badge: String?
    var lines: [Line] = []
    let amount: AmountPresentation

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var lineIconWidth: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon
                    texts
                }
                amountText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                icon
                texts
                Spacer(minLength: 8)
                amountText
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let symbolName {
            Image(systemName: symbolName)
                .foregroundStyle(.tint)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : iconWidth)
                .accessibilityIdentifier("row.icon")
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .accessibilityIdentifier("row.title")
            if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("row.badge")
            }
            ForEach(lines, id: \.kind) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: line.symbolName)
                        .font(.caption)
                        .frame(width: lineIconWidth)
                        .accessibilityHidden(true)
                    Text(line.text)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("row.\(line.kind.rawValue)")
            }
        }
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amountText: some View {
        AmountText(amount)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("row.amount")
    }
}

extension View {
    /// 沒有 ⋯ 的列也留 ⋯ 的位置(寬度跟 `MoreMenu` 一樣 44pt),同一個列表裡所有列的金額欄位置一致。
    func reservingMoreMenuSpace() -> some View {
        padding(.trailing, 44)
    }
}
