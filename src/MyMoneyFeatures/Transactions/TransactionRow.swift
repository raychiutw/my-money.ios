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
/// **只有無障礙字級才改成上下堆疊**(#128):圖示加標題、記帳人・歸屬、資產帳戶各一行(靠左)，**金額在最下面一行、靠右**;
/// 其他字級一律固定兩行，列高一致。金額一律單行。VoiceOver 整列念成一句完整的話。
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 無障礙字級才上下堆疊：圖示、標題、記帳人・歸屬、資產帳戶由上往下，金額最後一行、靠右。
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            titleText
                            subtitleText
                            accountText
                        }
                    }
                    amount
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    icon
                        .frame(width: iconWidth)
                    // 標題與次要文字拿剩下的寬度;金額與資產帳戶靠右，金額不被擠掉。
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        subtitleText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        amount
                        accountText
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenText)
        .accessibilityHint(lockHint ?? "")
    }

    private var icon: some View {
        Image(systemName: content.symbolName)
            .foregroundStyle(.tint)
    }

    private var titleText: some View {
        Text(content.title)
            .lineLimit(isOpenable ? 2 : nil)
    }

    /// 「記帳人・歸屬」固定一行:名稱先被截，歸屬不被截;無障礙字級改成折行、整句顯示。
    @ViewBuilder
    private var subtitleText: some View {
        let subtitle = content.subtitle
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 無障礙字級有的是縱向空間:整句折行顯示，不截斷。
                Text(subtitle.text)
            } else {
                // 記帳時間(#207)是最次要的資訊:整行放得下才顯示;放不下就省略時間,不能擠掉記帳人與歸屬(它們被截到剩一個字比沒有時間糟)。
                ViewThatFits(in: .horizontal) {
                    if let time = subtitle.time {
                        subtitleLine(recorder: subtitle.recorder, tail: subtitle.tail, time: time, truncatesRecorder: false)
                    }
                    subtitleLine(recorder: subtitle.recorder, tail: subtitle.tail, time: nil, truncatesRecorder: true)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    /// 「(時間・)記帳人・歸屬」一行;`truncatesRecorder` 時名稱放不下從結尾截(歸屬與標籤不被截)。
    @ViewBuilder
    private func subtitleLine(recorder: String?, tail: String, time: String?, truncatesRecorder: Bool) -> some View {
        HStack(spacing: 0) {
            if let time {
                Text("\(time)・").monospacedDigit().lineLimit(1).fixedSize()
            }
            if let recorder {
                if truncatesRecorder {
                    Text(recorder).lineLimit(1)
                } else {
                    Text(recorder).lineLimit(1).fixedSize()
                }
                Text("・\(tail)").lineLimit(1).fixedSize()
            } else {
                Text(tail).lineLimit(1)
            }
        }
    }

    /// 資產帳戶名稱;沒有帳戶名稱就不佔一行。
    @ViewBuilder
    private var accountText: some View {
        if let name = content.accountName {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // 無障礙字級有的是縱向空間:折行顯示、不截斷(HIG 盡量少截斷);其他字級單行、太長從結尾截斷。
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : accountMaxWidth,
                    alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
                )
        }
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amount: some View {
        AmountText(content.amount)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}
