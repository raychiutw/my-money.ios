import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，交易頁用(DESIGN.md「明細卡與輸入框」第三版,#288)。內容由 `TransactionRowContent` 決定，排版交給共用的 `EntryCard`:
/// 頭像(建檔人)｜標題(分類中文)｜⋯;膠囊(歸屬、銷帳或出帳狀態、帳戶)｜金額;備註一行。VoiceOver 整列念成一句完整的話。
struct TransactionRow: View {
    let content: TransactionRowContent
    /// 點不開的列(系統紀錄，或沒有編輯權限的他人交易，#133)的 VoiceOver 提示，例如「點兩下查看為什麼不能編輯」(#146);
    /// 原因在點了之後的說明，不塞在整句裡。可以改的列是 `nil`。
    var lockHint: String?
    /// 這一列右上角有沒有 ⋯(沒有編輯權限的列沒有):有才在第一排右邊讓出位置。
    var hasMenu = true

    @Environment(\.exposesRowPartsToAccessibility) private var exposesParts

    var body: some View {
        EntryCard(
            avatarInitial: content.avatarInitial, isSystemRecord: content.isSystemRecord, title: content.categoryTitle,
            chips: content.chips, amount: content.amount, note: content.note, reservesMenuSpace: hasMenu
        )
        .accessibilityElement(children: exposesParts ? .contain : .ignore)
        .accessibilityLabel(content.spokenText)
        .accessibilityHint(lockHint ?? "")
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
    /// 同一行相鄰兩個子視圖的水平間距。
    var spacing: CGFloat = 0
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
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (CGSize(width: maxWidth, height: y + lineHeight), frames)
    }
}

extension EnvironmentValues {
    /// UI 測試要量列裡每個部分(圖示、標題、次要文字、金額、帳戶)的位置(#246):只有 `-uiTestingRowParts` 時列才不把子元素合成一個，
    /// 各部分變成可查詢的元素。一般使用者永遠是 `false`。
    @Entry public var exposesRowPartsToAccessibility = false
}
