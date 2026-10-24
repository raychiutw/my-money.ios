import SwiftUI

/// 明細卡第三版(DESIGN.md「明細卡與輸入框」,#288):記帳頁、成員代墊明細、已結清明細、撥款沖帳紀錄、出帳預覽、報銷勾選明細共用。
///
/// 三排,排與排之間有分隔線:
/// 1. 頭像(建檔人名字第一個字;沒有就不放)｜標題(單行,超過用「…」;最大字級不限)｜右邊讓出 ⋯ 的位置。
/// 2. 膠囊(歸屬、銷帳或出帳狀態、帳戶…;一行放得下並排,放不下**整顆**換行,膠囊裡的字不折行,單顆比一行寬才在裡面加「…」)｜金額。
/// 3. 備註(單欄、整行、一行加「…」);沒有備註整排不出現。
///
/// ⋯ 由呼叫端用 `overlayMoreMenu(alignment: .topTrailing)` 蓋在第一排右邊,**⋯ 與金額同一個右欄、右緣對齊**(沒有 ⋯ 的列金額照樣在最右)。
/// 沒有圖示、沒有時間。結構只跟字級走、不跟資料長短走(#248):最大字級第二排改上下堆疊——膠囊整排、金額獨立一排(上面有分隔線、靠右)。
/// VoiceOver 由呼叫端用一句完整的話念(含收支方向)。
struct EntryCard: View {
    var avatarInitial: String?
    var isSystemRecord = false
    let title: String
    var chips: [String] = []
    let amount: AmountPresentation
    var note: String?
    /// 第一排右邊留給 ⋯ 的位置(沒有 ⋯ 的列不留)。
    var reservesMenuSpace = true

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if isLarge {
                if !chips.isEmpty { chipRow }
                if !chips.isEmpty { Divider() }
                amountText.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    chipRow
                    Spacer(minLength: 8)
                    amountText
                }
            }
            if let note, !note.isEmpty {
                Divider()
                Text(note)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("row.note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: isLarge ? .firstTextBaseline : .center, spacing: 10) {
            if let avatarInitial {
                Text(avatarInitial)
                    .font(.subheadline.weight(.bold))
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(isSystemRecord ? Color.secondary.opacity(0.2) : Color.ciFill.opacity(0.22)))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("row.avatar")
            }
            Text(title)
                .font(.headline)
                .lineLimit(isLarge ? nil : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("row.title")
            if reservesMenuSpace {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    private var chipRow: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                EntryChip(text: chip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("row.chips")
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

/// 一顆膠囊:字不折行,單顆比一行寬就在裡面加「…」。「待報銷」用淡粉色,其他是中性灰。
struct EntryChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(text == Terms.pendingReimbursement ? Color.ciText : Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(text == Terms.pendingReimbursement ? Color.ciFill.opacity(0.16) : Color.secondary.opacity(0.14))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}
