import MyMoneyDomain
import SwiftUI

/// toolbar 篩選選單的選項：視角、帳戶檢視範圍。`title` 是選單裡的文字，也是導覽列副標題。
protocol ScopeFilterOption: Hashable, CaseIterable {
    var title: String { get }
}

extension ViewScope: ScopeFilterOption {
    /// 視角的名稱(CONTEXT.md)。
    var title: String {
        switch self {
        case .all: "全部"
        case .household: "家庭公帳"
        case .personal: "個人"
        }
    }
}

extension AccountScope: ScopeFilterOption {
    /// 帳戶檢視範圍的名稱(CONTEXT.md)。
    public var title: String {
        switch self {
        case .all: "全部"
        case .household: "家庭公用"
        case .personal: "個人私帳"
        }
    }
}

/// toolbar 上的篩選按鈕：可勾選的選單(DESIGN.md「導覽」)。總覽、統計篩選視角(全部、家庭、個人),
/// 帳戶頁篩選帳戶檢視範圍(全部、家庭公用、個人私帳)。
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
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                // label 用 `Label` 時,toolbar 上的 `accessibilityValue` 會被丟掉(VoiceOver 念不到目前的選擇),
                // 所以只放 symbol,標籤另外用 `accessibilityLabel` 補上。
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel(name)
            .accessibilityValue(scope.title)
            .accessibilityIdentifier(identifier)
        }
    }
}
