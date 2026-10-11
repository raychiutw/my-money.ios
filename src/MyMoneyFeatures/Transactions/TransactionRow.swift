import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，交易頁用(DESIGN.md「列與欄位」,#72、#118、#145)。像 Wallet 的列:標題加一行次要文字，金額在右邊:
///
/// - 前緣：分類圖示。
/// - 標題：備註，沒有備註時用分類名稱;點得開的列最多兩行。
/// - 次要文字(固定一行):「記帳人・歸屬」,例如「小美・家庭公帳」;信用卡消費後面多一個帳單狀態「已出帳」「延至下期」(#188);
///   放不下先截記帳人的名稱，歸屬與標籤保留。
/// - trailing:帶正負號的金額，下面一行是資產帳戶名稱(次要文字、靠右、單行、太長從結尾截斷)。
///
/// 不再有金額旁邊的小圖示(家庭公帳、家人記的、鎖定):語意都寫成文字，點不開的列怎麼說明見 #146。
/// **放不下兩欄就上下堆疊**(#128、#246):無障礙字級一定堆疊;其他字級用 `ViewThatFits` 依實際寬度決定——左欄(標題與次要文字)
/// 至少要有 `minLeading` 寬才用兩欄，不然堆疊:圖示加標題、記帳人・歸屬、資產帳戶各一行(靠左)，**金額在最下面一行、靠右**。
/// 次要文字放不下一行時折成兩行(記帳人一行、歸屬與狀態一行)，不能比可用寬度寬。金額一律單行。VoiceOver 整列念成一句完整的話。
struct TransactionRow: View {
    let content: TransactionRowContent
    /// 點得開(可以編輯)的列：標題最多兩行，從結尾截斷。點不開的列不截斷，才看得到全文。
    var isOpenable = false
    /// 點不開的列(系統紀錄，或沒有編輯權限的他人交易，#133)的 VoiceOver 提示，例如「點兩下查看為什麼不能編輯」(#146);
    /// 原因在點了之後的說明，不塞在整句裡。可以改的列是 `nil`。
    var lockHint: String?

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    /// 資產帳戶名稱的最大寬度，跟著字級放大;更長的從結尾截斷，金額不被擠掉。
    @ScaledMetric(relativeTo: .subheadline) private var accountMaxWidth: CGFloat = 120
    /// 兩欄版型裡左欄(標題與次要文字)至少要有的寬度;騰不出來就改成上下堆疊(#246)。
    @ScaledMetric(relativeTo: .body) private var minLeading: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.exposesRowPartsToAccessibility) private var exposesParts

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                // 兩欄放得下就兩欄(左欄至少 `minLeading`);放不下改成上下堆疊，不能比螢幕寬(#246)。
                ViewThatFits(in: .horizontal) {
                    twoColumnLayout
                    stackedLayout
                }
            }
        }
        .accessibilityElement(children: exposesParts ? .contain : .ignore)
        .accessibilityLabel(content.spokenText)
        .accessibilityHint(lockHint ?? "")
    }

    /// 上下堆疊：圖示、標題、記帳人・歸屬、資產帳戶由上往下，金額最後一行、靠右。
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    subtitleText(stacked: true)
                    accountText(stacked: true)
                }
            }
            amount
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var twoColumnLayout: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: iconWidth)
            // 標題與次要文字拿剩下的寬度(至少 `minLeading`,理想寬度也是它，`ViewThatFits` 才不會被長標題的單行寬度擋掉);
            // 金額與資產帳戶靠右，金額不被擠掉。
            VStack(alignment: .leading, spacing: 2) {
                titleText
                subtitleText(stacked: false)
            }
            .frame(minWidth: minLeading, idealWidth: minLeading, maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                amount
                accountText(stacked: false)
            }
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

    /// 「記帳人・歸屬」固定一行:名稱先被截，歸屬不被截;無障礙字級改成折行、整句顯示。
    @ViewBuilder
    private func subtitleText(stacked: Bool) -> some View {
        let subtitle = content.subtitle
        Group {
            if dynamicTypeSize.isAccessibilitySize || stacked {
                // 堆疊(無障礙字級或兩欄放不下)有的是縱向空間:整句折行顯示，不截斷。
                Text(subtitle.text)
            } else {
                // 記帳時間(#207)是最次要的資訊:整行放得下才顯示;放不下就省略時間,不能擠掉記帳人與歸屬。
                // 一行都放不下時折成兩行(記帳人一行、歸屬與狀態一行)，歸屬與狀態不被截、也不能比可用寬度寬(#246)。
                ViewThatFits(in: .horizontal) {
                    if let time = subtitle.time {
                        subtitleLine(recorder: subtitle.recorder, tail: subtitle.tail, time: time)
                    }
                    subtitleLine(recorder: subtitle.recorder, tail: subtitle.tail, time: nil)
                    VStack(alignment: .leading, spacing: 0) {
                        if let recorder = subtitle.recorder { Text(recorder).lineLimit(1) }
                        Text(subtitle.tail)
                    }
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("row.subtitle")
    }

    /// 「(時間・)記帳人・歸屬」一行(整行放得下才會被選中)。
    @ViewBuilder
    private func subtitleLine(recorder: String?, tail: String, time: String?) -> some View {
        HStack(spacing: 0) {
            if let time {
                Text("\(time)・").monospacedDigit().lineLimit(1).fixedSize()
            }
            if let recorder {
                Text(recorder).lineLimit(1).fixedSize()
                Text("・\(tail)").lineLimit(1).fixedSize()
            } else {
                Text(tail).lineLimit(1).fixedSize()
            }
        }
    }

    /// 資產帳戶名稱;沒有帳戶名稱就不佔一行。
    @ViewBuilder
    private func accountText(stacked: Bool) -> some View {
        if let name = content.accountName {
            let wraps = dynamicTypeSize.isAccessibilitySize
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // 無障礙字級有的是縱向空間:折行顯示、不截斷(HIG 盡量少截斷);其他字級單行、太長從結尾截斷。
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.tail)
                .accessibilityIdentifier("row.account")
                .frame(
                    maxWidth: stacked ? .infinity : accountMaxWidth,
                    alignment: stacked ? .leading : .trailing
                )
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

extension EnvironmentValues {
    /// UI 測試要量列裡每個部分(圖示、標題、次要文字、金額、帳戶)的位置(#246):只有 `-uiTestingRowParts` 時列才不把子元素合成一個，
    /// 各部分變成可查詢的元素。一般使用者永遠是 `false`。
    @Entry public var exposesRowPartsToAccessibility = false
}
