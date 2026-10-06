import MyMoneyDomain

extension SavingsGoalIcon {
    /// 對應的 SF Symbol(跟分類圖示一樣用 SF Symbols,不用 emoji)。
    public var symbolName: String {
        switch self {
        case .target: "target"
        case .plane: "airplane"
        case .home: "house"
        case .car: "car"
        case .gem: "diamond"
        case .laptop: "laptopcomputer"
        case .baby: "figure.and.child.holdinghands"
        case .graduationCap: "graduationcap"
        case .heartPulse: "heart.text.square"
        case .palmtree: "beach.umbrella"
        case .backpack: "backpack"
        case .palette: "paintpalette"
        }
    }

    /// 選擇器的 VoiceOver 名稱。
    public var title: String {
        switch self {
        case .target: "目標"
        case .plane: "旅行"
        case .home: "住家"
        case .car: "汽車"
        case .gem: "珠寶"
        case .laptop: "電腦"
        case .baby: "寶寶"
        case .graduationCap: "學業"
        case .heartPulse: "健康"
        case .palmtree: "度假"
        case .backpack: "背包"
        case .palette: "藝術"
        }
    }
}
