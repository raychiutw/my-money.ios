import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension Color {
    /// 主要文字色的反色(系統背景色:淺色白、深色黑)。單色填滿的主要動作與選取格的字、圖示用它。
    static var inverseOfPrimary: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// 單色玻璃按鈕(#134、ADR-0007):互動元素不靠顏色表達，可點的東西靠 Liquid Glass 外框。
// 淺色黑字白底、深色白字黑底(accent 色是單色，見 AccentColor 資產);玻璃只給控制層(按鈕、工具列)，卡片、列、圖表不加。
//
// 驗證結果(研究筆記 §11):`.glass` 在淺色、深色、增強對比都正常;`.glassProminent` 的字色固定是白色，
// 深色模式 accent 是白色時會變成白底白字，所以主要動作的字要明確指定成反色(系統背景色)。

/// Sheet 左上的關閉鈕:✕ 玻璃圓鈕。VoiceOver 念「關閉」。
struct SheetCloseButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("關閉", systemImage: "xmark", role: .cancel, action: action)
        }
    }
}

/// Sheet 右上的確認鈕:✓ 單色填滿玻璃圓鈕，每個畫面只有這一個 primary action。VoiceOver 念 `title`(「儲存」「完成」等)。
/// 系統依 accent(單色)自動選反色的勾勾，淺色黑底白勾、深色白底黑勾。
struct SheetConfirmButton: ToolbarContent {
    let title: String
    var isDisabled = false
    let identifier: String
    let action: () -> Void

    init(_ title: String, isDisabled: Bool = false, identifier: String, action: @escaping () -> Void) {
        self.title = title
        self.isDisabled = isDisabled
        self.identifier = identifier
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(title, systemImage: "checkmark", role: .confirm, action: action)
                .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// 需要文字的主要動作(「登入」「ATM 提款／轉帳」):單色填滿的玻璃膠囊，淺色黑底白字、深色白底黑字。
/// `fillsWidth` 時撐滿一行。停用時系統會淡化。
struct PrimaryCapsuleButton: View {
    let title: String
    var systemImage: String?
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.body.weight(.semibold))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                // 明確的反色字:`.glassProminent` 的字色固定是白色，深色模式白底白字會看不見。
                .foregroundStyle(Color.inverseOfPrimary)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

/// 需要文字的次要動作(「轉帳」「前往帳戶管理」):玻璃膠囊，字是主要文字色。
struct GlassCapsuleButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}

/// 區塊標題右邊的「…」，點開選單(取代「管理」「全部」這類裸文字按鈕)。
/// 只有符號、**沒有外框**(使用者要求，#137、ADR-0007 的例外);點擊範圍 44×44pt(HIG),VoiceOver 念 `label`，例如「帳戶的更多動作」。
struct MoreMenu<Content: View>: View {
    let label: String
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
