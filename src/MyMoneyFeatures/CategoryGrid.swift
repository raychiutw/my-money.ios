import MyMoneyDomain
import SwiftUI

/// 分類的格狀選擇(ADR-0004、#89):全部攤開，每格是圖示加名稱，點一下就選，比下拉選單少一次點擊。
/// 記一筆、編輯交易和預算額度編輯共用。
///
/// 這是**刻意偏離 HIG**(超過約 5 個選項建議用 pop-up button),理由是少一次點擊,見 DESIGN.md「導覽」的「選擇控制項」。
///
/// 欄數由實際空間決定(`adaptive`),最小欄寬跟著字級放大，所以大字級自然變成比較少的欄，標籤不縮小也不截斷。
/// 選取的格子是主要文字色填滿加反色字與打勾(單色，#134)，不只靠顏色;VoiceOver 念分類名稱並標示已選取。
/// 目前的分類不在清單裡(例如機器人記帳寫入的舊分類)時，沒有任何一格被選取，也不會改動目前的值。
struct CategoryGrid: View {
    let categories: [TransactionCategory]
    @Binding var selection: TransactionCategory
    @ScaledMetric(relativeTo: .subheadline) private var minimumCellWidth = 72

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCellWidth), spacing: 8)], spacing: 8) {
            ForEach(categories, id: \.self) { category in
                cell(category)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ category: TransactionCategory) -> some View {
        let isSelected = category == selection
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            selection = category
        } label: {
            VStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .font(.title3)
                Text(category.name)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 4)
            // 選取單色化(#134):主要文字色填滿、字與圖示反色(淺色黑底白字、深色白底黑字);沒選的是細外框。
            .foregroundStyle(isSelected ? Color.inverseOfPrimary : Color.primary)
            .background(isSelected ? Color.primary : Color.clear, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .padding(4)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
