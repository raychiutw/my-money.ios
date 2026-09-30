import MyMoneyDomain

/// 支出分類圖表的顏色(DESIGN.md「顏色」):跟著分類固定，不隨排序、月份或視角改變。
///
/// 都是系統色，深色和增強對比由系統調整;紅色留給支出和超支，不用。
/// 11 種分類有專屬色;沒有專屬色的分類(美妝保養、寵物毛孩、社交人情、保險稅費、「其他」,
/// 以及清單外的舊分類)是 `gray`,畫圖時併進同一塊灰色。
public enum CategoryChartColor: Hashable, Sendable, CaseIterable {
    case orange, blue, purple, pink, green, cyan, yellow, indigo, teal, mint, brown, gray

    public init(category: TransactionCategory) {
        self = switch category.name {
        case "餐飲": .orange
        case "交通": .blue
        case "汽機車輛": .indigo
        case "居家水電": .teal
        case "數位訂閱": .mint
        case "購物": .pink
        case "生活": .green
        case "娛樂": .purple
        case "醫療": .cyan
        case "教育": .yellow
        case "旅行度假": .brown
        default: .gray
        }
    }

    /// 有專屬色的分類才會單獨成一塊。
    public var isDedicated: Bool { self != .gray }
}

/// 統計頁的支出分類圓餅圖(#100):最多 8 塊,16 種分類也讀得懂。
///
/// - 有專屬色的分類依金額由大到小，各自一塊，用自己固定的顏色。
/// - 沒有專屬色的分類永遠併進 1 塊灰色;有專屬色的分類超過 8 種時，金額最大的 7 種各自一塊，
///   其餘也併進這塊灰色。所以總共最多 8 塊。
/// - 下方清單仍列出全部分類，圓點顏色跟圖一致(合併進灰色的，圓點也是灰色)，所以不只靠顏色辨識。
public struct ExpenseChart: Sendable {
    /// 圖上的一塊。合併的灰色塊 `categories` 有好幾個分類。
    public struct Slice: Hashable, Sendable, Identifiable {
        public let name: String
        public let total: Money
        public let categories: [TransactionCategory]
        public let color: CategoryChartColor
        public let isMerged: Bool

        public var id: String { name }

        /// VoiceOver 念的名稱:合併的灰色塊念出它包含哪些分類。
        public var spokenName: String {
            isMerged ? "\(ExpenseChart.mergedName)，包含 \(categories.map(\.name).joined(separator: "、"))" : name
        }
    }

    /// 合併的灰色塊的名稱。
    public static let mergedName = "其餘分類"

    /// 圖最多幾塊。
    static let maximumSlices = 8

    public let slices: [Slice]

    public init(expenses: [CategoryExpense]) {
        // 金額由大到小;同金額時保持原本的順序(`sorted` 不保證穩定，所以自己帶 index)。
        let ordered = expenses.enumerated()
            .sorted { $0.element.total != $1.element.total ? $0.element.total > $1.element.total : $0.offset < $1.offset }
            .map(\.element)
        let dedicated = ordered.filter { CategoryChartColor(category: $0.category).isDedicated }
        let undedicated = ordered.filter { !CategoryChartColor(category: $0.category).isDedicated }

        // 沒有要併進灰色的分類，而且有專屬色的分類沒超過 8 種:全部各自一塊。
        let needsMerge = !undedicated.isEmpty || dedicated.count > Self.maximumSlices
        let single = needsMerge ? Array(dedicated.prefix(Self.maximumSlices - 1)) : dedicated
        let merged = needsMerge ? Array(dedicated.dropFirst(Self.maximumSlices - 1)) + undedicated : []

        var slices = single.map {
            Slice(
                name: $0.category.name, total: $0.total, categories: [$0.category],
                color: CategoryChartColor(category: $0.category), isMerged: false
            )
        }
        if !merged.isEmpty {
            slices.append(Slice(
                name: Self.mergedName, total: merged.reduce(.zero) { $0 + $1.total },
                categories: merged.map(\.category), color: .gray, isMerged: true
            ))
        }
        self.slices = slices
    }

    /// 清單裡這個分類的圓點顏色:單獨一塊的用自己的顏色，合併進灰色的(或圖上沒有的)是灰色。
    public func color(for category: TransactionCategory) -> CategoryChartColor {
        slices.first { !$0.isMerged && $0.categories == [category] }?.color ?? .gray
    }
}
