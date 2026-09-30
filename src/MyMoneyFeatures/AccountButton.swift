import SwiftUI

/// 頭像上的文字:姓名(去頭尾空白)的第一個字元，英文轉大寫;姓名是空的時候是 `nil`(改用人像圖示)。
///
/// 取的是「字元」(grapheme cluster)而不是 Unicode 純量，所以由多個純量組成的 emoji 不會被切壞。
public enum AvatarInitial {
    public static func text(for name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }
}

/// 打開「我的」sheet 的動作。包一層 struct,因為把閉包直接放進 `@Entry` 會讓相依的畫面每次更新都失效。
struct OpenAccountAction {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void = {}) {
        self.action = action
    }

    @MainActor
    func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    /// 由 tab 外殼提供，各 tab 主頁面 toolbar 的頭像按鈕呼叫它(DESIGN.md「導覽」)。
    @Entry var openAccount = OpenAccountAction()
}

/// 每個 tab 主頁面 toolbar 最右邊的頭像按鈕(ADR-0004)。獨立一組玻璃按鈕，不跟前面的按鈕併在一起。
///
/// 所有 tab 共用同一個 accessibility identifier,UI 測試不用依賴文字。VoiceOver 念「我的，姓名」。
struct AccountToolbarItem: ToolbarContent {
    @Environment(AppSession.self) private var session
    @Environment(\.openAccount) private var openAccount

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                openAccount()
            } label: {
                AvatarView(initial: AvatarInitial.text(for: name))
            }
            .accessibilityLabel(name.isEmpty ? "我的" : "我的，\(name)")
            .accessibilityIdentifier("toolbar.me")
        }
    }

    private var name: String {
        session.current?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// 姓名第一個字的圓形頭像;沒有文字時是人像圖示。字用 `subheadline`,圓圈跟著字級放大，大字級不會裁掉字。
private struct AvatarView: View {
    let initial: String?
    @ScaledMetric(relativeTo: .subheadline) private var size = 30

    var body: some View {
        if let initial {
            Text(initial)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.background)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.accentColor))
        } else {
            Image(systemName: "person.crop.circle")
        }
    }
}
