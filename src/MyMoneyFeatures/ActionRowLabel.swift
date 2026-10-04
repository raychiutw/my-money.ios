import SwiftUI

/// 清單裡一列動作的 label:最左邊一個圖示加文字,整列都點得開,不只文字的範圍(#76、#165)。
///
/// 純文字的列看起來跟標籤一樣,看不出可以按;有圖示才認得出是動作(HIG:按鈕要看得出可以按)。
/// 不用 `Label`:AX5 字級折成兩行會被裁掉、圖示壓到文字(#76 的截圖),改成自己排圖示和文字。
/// 圖示欄的寬度和間距跟 List 裡的 `Label` 差不多,文字對齊上面各列的名稱。
struct ActionRowLabel: View {
    let title: String
    let systemImage: String

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(title)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
