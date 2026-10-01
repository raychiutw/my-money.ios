import Foundation
import SwiftUI

/// 頭像的配色:字與底色都是**明確的 RGB**,不用語意色(尤其不用「背景色」):語意色在 Liquid Glass 的 toolbar 裡,
/// 真機與模擬器解析的結果不一樣(真機深色模式曾經字比圓還淺，對比只有 1.3:1,#106)。
/// 淺色、深色、增強對比各一組，對比都用 WCAG 公式驗證(單元測試)。純資料，不依賴 SwiftUI。
public struct AvatarPalette: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public let red: Int
        public let green: Int
        public let blue: Int

        public init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// WCAG 的相對亮度。
        var relativeLuminance: Double {
            func channel(_ value: Int) -> Double {
                let normalized = Double(value) / 255
                return normalized <= 0.03928 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }
    }

    public enum Style: CaseIterable, Sendable {
        case light, dark, lightIncreasedContrast, darkIncreasedContrast
    }

    /// 圓圈的底色。
    public let fill: RGB
    /// 圓圈裡的字色。
    public let letter: RGB

    public init(fill: RGB, letter: RGB) {
        self.fill = fill
        self.letter = letter
    }

    /// 字與底色的 WCAG 對比(1 到 21)。
    public var contrastRatio: Double {
        let first = fill.relativeLuminance
        let second = letter.relativeLuminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// 淺色:深酒紅底配白字(約 8:1);深色:淡粉紅底配近黑字(約 9.7:1);增強對比再拉開(都超過 10:1)。
    public static func palette(for style: Style) -> AvatarPalette {
        switch style {
        case .light:
            AvatarPalette(fill: RGB(red: 143, green: 45, blue: 58), letter: RGB(red: 255, green: 255, blue: 255))
        case .dark:
            AvatarPalette(fill: RGB(red: 255, green: 156, blue: 156), letter: RGB(red: 31, green: 5, blue: 7))
        case .lightIncreasedContrast:
            AvatarPalette(fill: RGB(red: 111, green: 29, blue: 42), letter: RGB(red: 255, green: 255, blue: 255))
        case .darkIncreasedContrast:
            AvatarPalette(fill: RGB(red: 255, green: 201, blue: 201), letter: RGB(red: 0, green: 0, blue: 0))
        }
    }
}

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

/// 每個 tab 主頁面 toolbar 最右邊的頭像按鈕(ADR-0004)。獨立一顆，不跟前面的按鈕併在一起，
/// 而且**沒有外面那層玻璃膠囊底**，只有圓形頭像本身，跟 Apple 自己的 app 一致(#106)。
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
                // 頭像本身是 30pt 的圓;觸控範圍至少 44×44pt(HIG),沒有玻璃底也不能變小。
                AvatarView(initial: AvatarInitial.text(for: name))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(name.isEmpty ? "我的" : "我的，\(name)")
            .accessibilityIdentifier("toolbar.me")
        }
        // 隱藏系統為 toolbar 項目加的共用玻璃背景:不要在頭像外面多一層半透明的膠囊底。
        .sharedBackgroundVisibility(.hidden)
    }

    private var name: String {
        session.current?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// 姓名第一個字的圓形頭像;沒有文字時是人像圖示。字用 text style,圓圈跟著字級放大，大字級不會裁掉字。
/// toolbar 上的小頭像和「我的」標頭的大頭像共用。
struct AvatarView: View {
    let initial: String?
    let font: Font
    @ScaledMetric private var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        initial: String?, baseSize: CGFloat = 30, font: Font = .subheadline.weight(.heavy),
        relativeTo style: Font.TextStyle = .subheadline
    ) {
        self.initial = initial
        self.font = font
        _size = ScaledMetric(wrappedValue: baseSize, relativeTo: style)
    }

    /// 依外觀與「增強對比」選配色;全部是明確的 RGB(`AvatarPalette`)。
    private var palette: AvatarPalette {
        switch (colorScheme, contrast) {
        case (.dark, .increased): .palette(for: .darkIncreasedContrast)
        case (.dark, _): .palette(for: .dark)
        case (_, .increased): .palette(for: .lightIncreasedContrast)
        default: .palette(for: .light)
        }
    }

    var body: some View {
        if let initial {
            Text(initial)
                .font(font)
                .foregroundStyle(palette.letter.color)
                .frame(width: size, height: size)
                .background(Circle().fill(palette.fill.color))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(palette.fill.color)
        }
    }
}

extension AvatarPalette.RGB {
    fileprivate var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
