import SwiftUI

// 玻璃按鈕(#134、ADR-0007,#147 以 ADR-0008 修正):按鈕一律**不填色**——背景跟主題底色一樣，只有 Liquid Glass 外框;
// 主要動作靠粗體與位置區分，不靠反白填滿。淺色黑字、深色白字(accent 色是單色，見 AccentColor 資產);
// 玻璃只給控制層(按鈕、工具列)，卡片、列、圖表不加。
//
// 驗證結果(研究筆記 §11):`.glass` 在淺色、深色、增強對比都正常。以前主要動作用 `.glassProminent` 單色填滿,
// 字色固定是白色，深色模式白底白字還要特地指定反色;使用者在真機看過後不要填色，所以整套反白填滿作廢。

/// Sheet 左上的關閉鈕:✕ 玻璃圓鈕。VoiceOver 念「關閉」。
struct SheetCloseButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("關閉", systemImage: "xmark", role: .cancel, action: action)
        }
    }
}

/// Sheet 右上的確認鈕:✓ 玻璃圓鈕，跟左上的 ✕ 一樣不填色，靠勾勾與 VoiceOver 標籤區分，每個畫面只有這一個確認。
/// VoiceOver 念 `title`(「儲存」「完成」等)。不加 `role: .confirm`、也不放 `.confirmationAction`:這兩個在 iOS 26 都會自動畫成 accent 填滿的主要動作鈕,所以放 `.primaryAction`。
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
        ToolbarItem(placement: .primaryAction) {
            Button(title, systemImage: "checkmark", action: action)
                .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// 需要文字的主要動作(「登入」「ATM 提款／轉帳」):玻璃膠囊，不填色，字是粗體。`fillsWidth` 時撐滿一行。停用時系統會淡化。
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
        }
        .buttonStyle(.glass)
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
