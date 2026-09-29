import MyMoneyDomain
import SwiftUI

extension ViewScope {
    /// 視角的名稱(CONTEXT.md):篩選選單的選項，也是導覽列副標題。
    var title: String {
        switch self {
        case .all: "全部"
        case .household: "家庭"
        case .personal: "個人"
        }
    }
}

/// 總覽、統計 toolbar 上的視角篩選按鈕：可勾選的選單，選項是全部、家庭、個人(DESIGN.md「導覽」)。
///
/// 目前的選擇由畫面用 `.navigationSubtitle(scope.title)` 顯示在導覽列副標題。VoiceOver 念「視角」和目前的選擇。
struct ViewScopeFilter: ToolbarContent {
    @Binding var scope: ViewScope
    let identifier: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("視角", selection: $scope) {
                    ForEach(ViewScope.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                // label 用 `Label` 時,toolbar 上的 `accessibilityValue` 會被丟掉(VoiceOver 念不到目前的選擇),
                // 所以只放 symbol,標籤另外用 `accessibilityLabel` 補上。
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("視角")
            .accessibilityValue(scope.title)
            .accessibilityIdentifier(identifier)
        }
    }
}
