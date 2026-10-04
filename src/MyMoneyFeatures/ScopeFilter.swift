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
    /// 預設的視角是「全部」;其他就是套用了篩選(篩選按鈕改粉紅空心圓圈，#107、#147)。
    public var isDefaultFilter: Bool { self == .all }
}

extension AccountScope {
    /// 預設的檢視範圍是「全部」;其他就是套用了篩選(篩選按鈕改粉紅空心圓圈，#107、#147)。
    public var isDefaultFilter: Bool { self == .all }
}

/// 篩選按鈕的圖示(#147、ADR-0008):沒套用篩選是一般的三條線(主要文字色);套用了非預設篩選時改成
/// **品牌粉紅的空心圓圈**,圓圈的有無讓人不只靠顏色分辨(DESIGN.md「導覽」)。不填色,所以不是實心圓。
public enum FilterIcon {
    public static func symbolName(isActive: Bool) -> String {
        isActive ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease"
    }
}

/// 篩選按鈕 toolbar 上的圖示:套用中是品牌粉紅,否則是主要文字色。
struct FilterIconImage: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: FilterIcon.symbolName(isActive: isActive))
            .foregroundStyle(isActive ? Color.ciText : Color.primary)
    }
}

extension ViewScope: ScopeFilterOption {
    /// 視角的名稱:全部、家庭公帳、個人私帳(CONTEXT.md、#150;上游 ADR 0014 的短名不採用)。
    var title: String {
        switch self {
        case .all: "全部"
        case .household: OwnershipName.household
        case .personal: OwnershipName.personal
        }
    }

    /// 全部是地球、家庭公帳是房子、個人私帳是鎖(上游 ADR 0014 的 🌐🏠🔒)。
    var symbolName: String {
        switch self {
        case .all: "globe"
        case .household: "house"
        case .personal: "lock"
        }
    }
}

extension AccountScope: ScopeFilterOption {
    /// 帳戶檢視範圍的名稱:全部、家庭公帳、個人私帳(CONTEXT.md、#150)。
    public var title: String {
        switch self {
        case .all: "全部"
        case .household: OwnershipName.household
        case .personal: OwnershipName.personal
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

/// toolbar 上的篩選按鈕：可勾選的選單(DESIGN.md「導覽」)。總覽、統計篩選視角(全部、家庭公帳、個人私帳),
/// 帳戶頁篩選帳戶檢視範圍(全部、家庭公帳、個人私帳)。
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
                FilterIconImage(isActive: !scope.isDefaultFilter)
            }
            // 選單裡勾選的項目，勾勾維持系統樣式:系統選單的勾勾不吃 tint(試過 `.tint(.ciText)`,
            // 只有選項前面的符號變粉紅，勾勾還是白的)，不為了這個自己重做選單(#147、ADR-0008)。
            .accessibilityLabel(name)
            .accessibilityValue(scope.title)
            .accessibilityIdentifier(identifier)
        }
    }
}
