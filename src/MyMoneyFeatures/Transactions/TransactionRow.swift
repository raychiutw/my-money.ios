import MyMoneyDomain
import SwiftUI

/// 一筆交易記錄，交易頁用(DESIGN.md「列與欄位」,#72、#118)。數字優先，只留最重要的:
///
/// - 前緣：分類圖示。
/// - 名稱：備註，沒有備註時用分類名稱。
/// - 小標記(只有圖示、不用文字):家庭公帳 `house.fill` 或個人私帳 `person.fill`;家人記的加 `person.2.fill`。
/// - trailing:帶正負號的金額;系統紀錄在金額前面加鎖定標記。
///
/// 資產帳戶名稱與記帳人從列上拿掉(點進編輯可以看到)，但 VoiceOver 照樣念出，整列是一句完整的話。
/// **只有無障礙字級才改成上下堆疊**(#128)，其他字級一律單行:名稱在左(最多兩行)、小標記與金額靠右;金額一律單行。
/// 以前用 `ViewThatFits` 依寬度判斷，XXL、XXXL 時小標記一多就掉進堆疊，列高變成兩倍以上。
struct TransactionRow: View {
    let transaction: MyMoneyDomain.Transaction
    /// 記帳人;自己記的是 `nil`。只用來決定要不要「家人記的」小標記和 VoiceOver 念誰記的。
    var recorder: String?
    /// 點得開(可以編輯)的列：名稱最多兩行，從結尾截斷。點不開的列不截斷，才看得到全文。
    var isOpenable = false
    /// 點不開的列(系統紀錄，或沒有編輯權限的他人交易，#133):金額前面加鎖定標記，VoiceOver 最後念這段說明，
    /// 例如「系統紀錄，不能編輯或刪除」(#63)。標記只有一個圖示，不影響單行版型(#128)。
    var lockReason: String?

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 無障礙字級才上下堆疊：圖示和名稱一行，金額、小標記各一行，用滿整列的寬度。
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        icon
                        titleText
                    }
                    amount
                    markers
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    icon
                        .frame(width: iconWidth)
                    // 名稱拿剩下的寬度，太長就從結尾截斷(最多兩行);標記與金額不被擠掉。
                    titleText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    markers
                    amount
                }
            }
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

    /// 家庭公帳或個人私帳，家人記的多一個標記;只有圖示，文字在 VoiceOver。
    private var markers: some View {
        HStack(spacing: 6) {
            Image(systemName: transaction.isShared ? "house.fill" : "person.fill")
            if recorder != nil {
                Image(systemName: "person.2.fill")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    /// 金額一律單行，不能被拆成多行(DESIGN.md「列與欄位」)。
    private var amount: some View {
        HStack(spacing: 4) {
            if lockReason != nil {
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

    private var title: String { transaction.displayTitle }

    private var account: String {
        transaction.accountName ?? "預設帳戶"
    }

    /// 例如「餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元」。沒有備註時不重複念分類。
    private var spokenText: String {
        var parts = [transaction.category.name]
        if !transaction.note.isEmpty { parts.append(transaction.note) }
        parts.append("帳戶 \(account)")
        if let recorder { parts.append("記帳人 \(recorder)") }
        parts.append(OwnershipName.title(isShared: transaction.isShared))
        parts.append(transaction.spokenAmount)
        if let lockReason { parts.append(lockReason) }
        return parts.joined(separator: "，")
    }
}
