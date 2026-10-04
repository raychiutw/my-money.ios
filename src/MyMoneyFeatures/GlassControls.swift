import SwiftUI

// 玻璃按鈕(#134、ADR-0007，ADR-0008 修正，ADR-0009 再修正):一般按鈕(✕、工具列、次要膠囊)**不填色**——只有 Liquid Glass 外框,
// 次要膠囊的字是 CI 文字色;**✓ 與主要按鈕填 CI 色**(`ciFill`，淺色與深色同一個)，勾勾與字固定用 `ciGlyph`(白，
// 只有深色增強對比是黑)——不像 ADR-0007 的單色填滿，深色模式不必特例。玻璃只給控制層(按鈕、工具列)，卡片、列、圖表不加。

/// Sheet 左上的關閉鈕:✕ 玻璃圓鈕。VoiceOver 念「關閉」。
struct SheetCloseButton: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("關閉", systemImage: "xmark", role: .cancel, action: action)
        }
    }
}

/// Sheet 右上的確認鈕:✓ 圓鈕**填 CI 色**(`ciFill`)、勾勾反白(ADR-0009)，左上的 ✕ 維持不填色的玻璃;每個畫面只有這一個確認。
/// VoiceOver 念 `title`(「儲存」「完成」等)。仍放 `.primaryAction`、不加 `role: .confirm`:`.confirmationAction` 與 `.confirm` 會自動畫成 accent(黑／白)填滿，蓋掉 CI 色。
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
            Button(action: action) {
                Label(title, systemImage: "checkmark")
                    .foregroundStyle(Color.ciGlyph)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ciFill)
            .disabled(isDisabled)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// 需要文字的主要動作(「登入」「ATM 提款／轉帳」):**CI 填色**(`ciFill`)的膠囊，反白粗體字(`ciGlyph`)。`fillsWidth` 時撐滿一行。停用時系統會淡化。一個畫面一個主要動作。
struct PrimaryCapsuleButton: View {
    let title: String
    var systemImage: String?
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ciGlyph)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.ciFill)
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

/// 需要文字的次要動作(「重試」「前往帳戶管理」「存入」):玻璃膠囊，不填色，字是 CI 文字色(`ciText`)。
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
        .foregroundStyle(Color.ciText)
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
