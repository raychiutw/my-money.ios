import MyMoneyDomain
import SwiftUI

extension TransactionCategory {
    /// 分類圖示(DESIGN.md「分類圖示」)。不在清單中的分類(例如機器人記帳寫入的)用 `tag`。
    var symbolName: String {
        switch name {
        case "餐飲": "fork.knife"
        case "交通": "tram.fill"
        case "娛樂": "gamecontroller"
        case "購物": "bag"
        case "生活": "lightbulb"
        case "醫療": "cross.case"
        case "教育": "book"
        case "薪資": "banknote"
        case "獎金": "gift"
        case "投資": "chart.line.uptrend.xyaxis"
        case "兼職": "briefcase"
        case "其他": "shippingbox"
        case "信用卡還款": "creditcard.and.123"
        default: "tag"
        }
    }
}

extension MyMoneyDomain.Transaction {
    /// 帶正負號的金額，例如 `+$45,000`、`-$120`。
    var signedAmountText: String {
        (type == .income ? "+" : "-") + amount.formatted()
    }

    /// VoiceOver 念的金額，例如「支出 120 元」(DESIGN.md「無障礙」)。
    var spokenAmount: String {
        (type == .income ? "收入 " : "支出 ") + amount.spokenText
    }

    var amountColor: Color {
        type == .income ? .green : .red
    }
}

/// 家庭公帳或個人私帳的標記：symbol 加文字，不只靠顏色(DESIGN.md「顏色」)。
struct LedgerBadge: View {
    let isShared: Bool

    var body: some View {
        Label(isShared ? "家庭公帳" : "個人私帳", systemImage: isShared ? "house.fill" : "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}
