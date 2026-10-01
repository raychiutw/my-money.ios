import MyMoneyDomain
import SwiftUI

extension CreditCard {
    /// 精簡列的第 2 行，只放一項(#73):信用卡待繳總額是 0 時是「已全數結清」,有待繳時是繳款日;
    /// 有待繳但沒有設定繳款日時沒有第 2 行。
    public var summaryLine: String? {
        guard totalDue > .zero else { return "已全數結清" }
        return paymentDueDay.map { "每月 \($0) 日繳款" }
    }

    /// 歸屬：家庭信用卡或個人卡(web 的 `bd0507b` 起一律標示)。
    var ownershipTitle: String { isJointFund ? "家庭信用卡" : "個人卡" }
    var ownershipSymbol: String { isJointFund ? "house.fill" : "person.fill" }
}

/// 信用卡精簡列，帳戶頁和總覽「帳戶一覽」共用(#73,DESIGN.md「列與欄位」)。整列是導覽連結，點進信用卡詳細頁。
///
/// - 前緣：代表色。跟同一區的其他列一致：帳戶頁是色條，總覽是信用卡圖示。
/// - 第 1 行：名稱。
/// - 第 2 行：只放一項，繳款日或「已全數結清」(`summaryLine`)。
/// - trailing:信用卡待繳總額(有待繳時用紅色，web 的 Dashboard 在 `82d9124` 起),下面是歸屬。
///
/// 用 `LabeledContent`:大字級放不下時自動改成上下堆疊。VoiceOver 把整列念成一句話。
struct CreditCardSummaryRow: View {
    enum Mark {
        /// 帳戶頁：跟現金錢包、銀行存款帳戶列一樣的色條。
        case colorBar
        /// 總覽：跟帳戶一覽其他列一樣，用代表色的類型圖示。
        case symbol
    }

    let card: CreditCard
    let mark: Mark

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                // 金額一律單行(DESIGN.md「列與欄位」)。
                Text(card.totalDue.formatted())
                    .monospacedDigit()
                    .foregroundStyle(card.totalDue > .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .fixedSize()
                Label(card.ownershipTitle, systemImage: card.ownershipSymbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        } label: {
            switch mark {
            case .colorBar:
                HStack(spacing: 12) {
                    AccountColorMark(hex: card.colorHex)
                    texts
                }
            case .symbol:
                Label {
                    texts
                } icon: {
                    Image(systemName: "creditcard")
                        .foregroundStyle(Color(hex: card.colorHex) ?? .gray)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// 點得開的列：名稱最多兩行，第 2 行一行，從結尾截斷(DESIGN.md「列與欄位」)。
    /// 無障礙字級時第 2 行可以折行：AX5 一行放不下「每月 5 日繳款」(HIG Typography:
    /// 「Keep text truncation to a minimum as font size increases」)。
    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.name)
                .lineLimit(2)
            if let line = card.summaryLine {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    /// 例如「iOS 測試信用卡，個人卡，信用卡待繳總額 15,500 元，每月 5 日繳款」。
    private var spokenText: String {
        var parts = [card.name, card.ownershipTitle, "信用卡待繳總額 \(card.totalDue.spokenText)"]
        if let line = card.summaryLine { parts.append(line) }
        return parts.joined(separator: "，")
    }
}

/// 使用者選的資產帳戶代表色。只是輔助辨識，不是唯一的資訊(DESIGN.md「顏色」)。
struct AccountColorMark: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 6, height: 28)
            .accessibilityHidden(true)
    }
}
