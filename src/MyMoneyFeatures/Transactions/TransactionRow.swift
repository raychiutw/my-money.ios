import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，交易頁用(DESIGN.md「列與欄位」,#72、#118、#145)。像 Wallet 的列:標題加一行次要文字，金額在右邊:
///
/// - 前緣：分類圖示。
/// - 標題：備註，沒有備註時用分類名稱;點得開的列最多兩行。
/// - 次要文字:「記帳時間・記帳人・歸屬」(信用卡消費後面多帳單狀態)，每個語意單位不拆開，放不下整個換到下一行。
/// - 資產帳戶名稱:文字欄的最後一行(次要文字，太長折行、不截斷)。
/// - trailing:帶正負號的金額，跟標題同一行、單行不被擠掉。
///
/// **結構只跟字級走、不跟資料長短走**(#248,HIG Lists and tables:資訊階層與間距一致、盡量少截斷、大字級改上下堆疊、列可以變高):
/// 無障礙字級上下堆疊——圖示加文字欄、**金額在最下面一行、靠右**;其他字級一律兩欄，同一個畫面裡每一列的金額、帳戶位置都一樣。
/// 不再有金額旁邊的小圖示(家庭公帳、家人記的、鎖定):語意都寫成文字，點不開的列怎麼說明見 #146。VoiceOver 整列念成一句完整的話。
struct TransactionRow: View {
    let content: TransactionRowContent
    /// 點得開(可以編輯)的列：標題最多兩行，從結尾截斷。點不開的列不截斷，才看得到全文。
    var isOpenable = false
    /// 點不開的列(系統紀錄，或沒有編輯權限的他人交易，#133)的 VoiceOver 提示，例如「點兩下查看為什麼不能編輯」(#146);
    /// 原因在點了之後的說明，不塞在整句裡。可以改的列是 `nil`。
    var lockHint: String?

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.exposesRowPartsToAccessibility) private var exposesParts

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                twoColumnLayout
            }
        }
        .accessibilityElement(children: exposesParts ? .contain : .ignore)
        .accessibilityLabel(content.spokenText)
        .accessibilityHint(lockHint ?? "")
    }

    /// 無障礙字級:圖示、標題、記帳人・歸屬、資產帳戶由上往下，金額最後一行、靠右。
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon
                texts
            }
            amount
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 其他字級:圖示、文字欄(標題、記帳人・歸屬、資產帳戶)、金額在右邊跟標題同一行。結構不看資料長短(#248):
    /// 文字欄拿剩下的寬度，太長就在欄內折行，金額單行不被擠掉。
    private var twoColumnLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            icon
                .frame(width: iconWidth)
            texts
            Spacer(minLength: 0)
            amount
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText
            subtitleText
            accountText
        }
    }

    private var icon: some View {
        Image(systemName: content.symbolName)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("row.icon")
    }

    private var titleText: some View {
        Text(content.title)
            .lineLimit(isOpenable ? 2 : nil)
            .accessibilityIdentifier("row.title")
    }

    /// 「(時間・)記帳人・歸屬」:每個語意單位(時間、記帳人、歸屬與狀態)是一個不拆開的 `Text`，放不下整段換到下一行，
    /// 不在單位中間折行(中文在任何兩個字之間都能折)。
    private var subtitleText: some View {
        let subtitle = content.subtitle
        let units = [subtitle.time, subtitle.recorder, subtitle.tail].compactMap { $0 }
        return WrappingUnits(units: units)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("row.subtitle")
    }

    /// 資產帳戶名稱;沒有帳戶名稱就不佔一行。在文字欄最後一行，太長折行、不截斷。
    @ViewBuilder
    private var accountText: some View {
        if let name = content.accountName {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("row.account")
        }
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amount: some View {
        AmountText(content.amount)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("row.amount")
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
