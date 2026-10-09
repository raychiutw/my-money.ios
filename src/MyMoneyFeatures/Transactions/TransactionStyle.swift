import MyMoneyDomain
import SwiftUI

extension TransactionCategory {
    /// 分類圖示(DESIGN.md「分類圖示」),標準分類 23 種各有專屬圖示。不在清單中的分類(例如機器人記帳寫入的)用 `tag`。
    public var symbolName: String {
        switch name {
        case "餐飲": "fork.knife"
        case "交通": "tram.fill"
        case "汽機車輛": "car"
        case "居家水電": "bolt.fill"
        case "數位訂閱": "iphone"
        case "購物": "bag"
        case "生活": "lightbulb"
        case "娛樂": "gamecontroller"
        case "美妝保養": "paintbrush.pointed"
        case "醫療": "cross.case"
        case "教育": "book"
        case "寵物毛孩": "pawprint"
        case "旅行度假": "airplane"
        case "社交人情": "person.2"
        case "保險稅費": "doc.text"
        case "薪資": "banknote"
        case "獎金": "gift"
        case "投資": "chart.line.uptrend.xyaxis"
        case "兼職": "briefcase"
        case "政府補貼": "building.columns"
        case "禮金餽贈": "envelope"
        case "二手出清": "arrow.3.trianglepath"
        case "其他": "shippingbox"
        case "信用卡還款": "creditcard.and.123"
        default: "tag"
        }
    }
}

extension MyMoneyDomain.Transaction {
    /// 金額的呈現(#208):收入綠色 `+$45,000`、支出紅色 `−$120`。
    var amountPresentation: AmountPresentation {
        type == .income ? .inflow(amount) : .outflow(amount)
    }
}

/// 公帳或私帳的標記：symbol 加文字，不只靠顏色(DESIGN.md「顏色」)。
struct LedgerBadge: View {
    let isShared: Bool

    var body: some View {
        Label(OwnershipName.title(isShared: isShared), systemImage: isShared ? "house.fill" : "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}
