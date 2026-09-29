import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，總覽的最近交易和交易頁共用(DESIGN.md「列與欄位」,#72)。一行一個欄位：
///
/// - 前緣：分類圖示。
/// - 第 1 行：備註，沒有備註時用分類名稱。
/// - 第 2 行：資產帳戶名稱，不加「帳戶：」。
/// - 第 3 行：記帳人，只有不是自己記的才有(由畫面 model 判斷)。
/// - trailing:帶正負號的金額，下面是家庭公帳或個人私帳的標記;系統紀錄在金額前面加鎖定標記。
///
/// 放不下時(大字級)改成上下堆疊，金額一律單行。VoiceOver 把整列念成一句完整的話。
struct TransactionRow: View {
    let transaction: MyMoneyDomain.Transaction
    /// 記帳人;自己記的是 `nil`。
    var recorder: String?
    /// 點得開(可以編輯)的列：備註最多兩行、帳戶和記帳人各一行，從結尾截斷。點不開的列不截斷，才看得到全文。
    var isOpenable = false
    /// 系統紀錄(不能編輯或刪除):金額前面加鎖定標記，VoiceOver 最後念「系統紀錄，不能編輯或刪除」(#63)。
    var isLocked = false

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    /// 左右並列時，文字欄至少要有的寬度，跟著字級變大;放不下就改成上下堆疊。
    ///
    /// 不用 `LabeledContent`:它依 label 不折行的寬度判斷，備註一長，預設字級也會變成上下堆疊(#72 的截圖)。
    @ScaledMetric(relativeTo: .body) private var minimumTextWidth: CGFloat = 120

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    details
                }
                .frame(minWidth: minimumTextWidth, idealWidth: minimumTextWidth, maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    amount
                    LedgerBadge(isShared: transaction.isShared)
                }
            }
            // 上下堆疊：圖示和備註一行，其餘各佔一行，用滿整列的寬度。
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon
                    titleText
                }
                details
                amount
                LedgerBadge(isShared: transaction.isShared)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var icon: some View {
        Image(systemName: transaction.category.symbolName)
            .foregroundStyle(.tint)
    }

    private var titleText: some View {
        Text(title)
            .lineLimit(isOpenable ? 2 : nil)
    }

    @ViewBuilder
    private var details: some View {
        Text(account)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(isOpenable ? 1 : nil)
        if let recorder {
            Label(recorder, systemImage: "person")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(isOpenable ? 1 : nil)
        }
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amount: some View {
        HStack(spacing: 4) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(transaction.signedAmountText)
                .monospacedDigit()
                .foregroundStyle(transaction.amountColor)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var title: String {
        transaction.note.isEmpty ? transaction.category.name : transaction.note
    }

    private var account: String {
        transaction.accountName ?? "預設帳戶"
    }

    /// 例如「餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元」。沒有備註時不重複念分類。
    private var spokenText: String {
        var parts = [transaction.category.name]
        if !transaction.note.isEmpty { parts.append(transaction.note) }
        parts.append("帳戶 \(account)")
        if let recorder { parts.append("記帳人 \(recorder)") }
        parts.append(transaction.isShared ? "家庭公帳" : "個人私帳")
        parts.append(transaction.spokenAmount)
        if isLocked { parts.append("系統紀錄，不能編輯或刪除") }
        return parts.joined(separator: "，")
    }
}
