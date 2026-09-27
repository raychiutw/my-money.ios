import SwiftUI

/// 還沒實作的功能先顯示這個佔位畫面，後續的票再換成真的畫面。
struct ComingSoonView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            "即將推出",
            systemImage: "hammer",
            description: Text("「\(title)」還在開發中。")
        )
        .navigationTitle(title)
    }
}
