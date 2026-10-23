import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，交易頁用(DESIGN.md「明細卡與輸入框」方案 B,#72、#118、#145、#280)。內容由 `TransactionRowContent` 決定，
/// 排版交給共用的 `EntryCard`:
///
/// - 前緣:分類圖示。標題:備註，沒有備註時用分類名稱，最多兩行。
/// - 標題下方:狀態膠囊「歸屬(・帳單狀態)」，例如「家庭公帳・待報銷」。
/// - 時間、記帳人、資產帳戶各占一行、不連成一排。金額固定在最右欄、單行，跟標題同一行。
///
/// **結構只跟字級走、不跟資料長短走**(#248):無障礙字級上下堆疊、金額最後一行靠右。VoiceOver 整列念成一句完整的話。
struct TransactionRow: View {
    let content: TransactionRowContent
    /// 點不開的列(系統紀錄，或沒有編輯權限的他人交易，#133)的 VoiceOver 提示，例如「點兩下查看為什麼不能編輯」(#146);
    /// 原因在點了之後的說明，不塞在整句裡。可以改的列是 `nil`。
    var lockHint: String?

    @Environment(\.exposesRowPartsToAccessibility) private var exposesParts

    var body: some View {
        EntryCard(
            symbolName: content.symbolName, title: content.title, badge: content.subtitle.tail,
            lines: lines, amount: content.amount
        )
        .accessibilityElement(children: exposesParts ? .contain : .ignore)
        .accessibilityLabel(content.spokenText)
        .accessibilityHint(lockHint ?? "")
    }

    /// 時間、記帳人、資產帳戶,沒有資料的不出現。
    private var lines: [EntryCard.Line] {
        let subtitle = content.subtitle
        return [
            subtitle.time.map { EntryCard.Line(kind: .time, text: $0) },
            subtitle.recorder.map { EntryCard.Line(kind: .recorder, text: $0) },
            content.accountName.map { EntryCard.Line(kind: .account, text: $0) },
        ].compactMap { $0 }
    }
}

/// 一串不可拆開的文字單位，用「・」接起來:一行放得下就同一行，放不下整個單位換下一行(最後一個單位後面不放「・」)。
struct WrappingUnits: View {
    let units: [String]

    var body: some View {
        FlowLayout(lineSpacing: 0) {
            ForEach(Array(units.enumerated()), id: \.offset) { index, unit in
                Text(index < units.count - 1 ? "\(unit)・" : unit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 由左到右排，放不下換行;單一子視圖比一行寬時，只給它一行的寬度(它自己在內部折行)。
struct FlowLayout: Layout {
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(size.width, width)
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, x)
        }
        return (CGSize(width: maxWidth, height: y + lineHeight), frames)
    }
}

extension EnvironmentValues {
    /// UI 測試要量列裡每個部分(圖示、標題、次要文字、金額、帳戶)的位置(#246):只有 `-uiTestingRowParts` 時列才不把子元素合成一個，
    /// 各部分變成可查詢的元素。一般使用者永遠是 `false`。
    @Entry public var exposesRowPartsToAccessibility = false
}
