import MyMoneyDomain
import SwiftUI

/// toolbar 篩選選單的選項：視角、帳戶檢視範圍。`title` 是選單裡的文字，也是導覽列副標題。
protocol ScopeFilterOption: Hashable, CaseIterable {
    var title: String { get }
    /// 選單項目前面的 SF Symbol(地球、房子、鎖;上游用 emoji，iOS 用 SF Symbols)。
    var symbolName: String { get }
    /// 是不是預設的選擇;不是的時候篩選按鈕改實心圖示。
    var isDefaultFilter: Bool { get }
}

extension ViewScope {
    /// 預設的視角是「全部」;其他就是套用了篩選(篩選按鈕改實心圖示，#107)。
    public var isDefaultFilter: Bool { self == .all }
}

extension AccountScope {
    /// 預設的檢視範圍是「全部」;其他就是套用了篩選(篩選按鈕改實心圖示，#107)。
    public var isDefaultFilter: Bool { self == .all }
}

/// 篩選按鈕的圖示:預設用一般的圖示，套用了非預設篩選時改實心，不只靠顏色(DESIGN.md「導覽」)。
func filterSymbolName(isActive: Bool) -> String {
    isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease"
}

extension ViewScope: ScopeFilterOption {
    /// 視角的名稱:全部、公帳、私帳(上游 ADR 0014，#138;CONTEXT.md)。
    var title: String {
        switch self {
        case .all: "全部"
        case .household: "公帳"
        case .personal: "私帳"
        }
    }

    /// 全部是地球、公帳是房子、私帳是鎖(上游 ADR 0014 的 🌐🏠🔒)。
    var symbolName: String {
        switch self {
        case .all: "globe"
        case .household: "house"
        case .personal: "lock"
        }
    }
}

extension AccountScope: ScopeFilterOption {
    /// 帳戶檢視範圍的名稱:全部、公帳、私帳(上游 ADR 0014，#138;CONTEXT.md)。
    public var title: String {
        switch self {
        case .all: "全部"
        case .household: "公帳"
        case .personal: "私帳"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "globe"
        case .household: "house"
        case .personal: "lock"
        }
    }
}

/// toolbar 上的篩選按鈕：可勾選的選單(DESIGN.md「導覽」)。總覽、統計篩選視角(全部、公帳、私帳),
/// 帳戶頁篩選帳戶檢視範圍(全部、公帳、私帳)。
///
/// 目前的選擇由畫面用 `.navigationSubtitle(scope.title)` 顯示在導覽列副標題。VoiceOver 念篩選的名稱(例如「視角」)和目前的選擇。
struct ScopeFilter<Scope: ScopeFilterOption>: ToolbarContent {
    /// 篩選的是什麼，例如「視角」「帳戶檢視範圍」:VoiceOver 的標籤，也是選單的標題。
    let name: String
    @Binding var scope: Scope
    let identifier: String

    init(_ name: String, scope: Binding<Scope>, identifier: String) {
        self.name = name
        _scope = scope
        self.identifier = identifier
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(name, selection: $scope) {
                    ForEach(Array(Scope.allCases), id: \.self) { option in
                        Label(option.title, systemImage: option.symbolName).tag(option)
                    }
                }
            } label: {
                // label 用 `Label` 時,toolbar 上的 `accessibilityValue` 會被丟掉(VoiceOver 念不到目前的選擇),
                // 所以只放 symbol,標籤另外用 `accessibilityLabel` 補上。
                Image(systemName: filterSymbolName(isActive: !scope.isDefaultFilter))
            }
            .accessibilityLabel(name)
            .accessibilityValue(scope.title)
            .accessibilityIdentifier(identifier)
        }
    }
}
