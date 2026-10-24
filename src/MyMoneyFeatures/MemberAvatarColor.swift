import SwiftUI

/// 成員頭像的顏色(#307):同一個人在明細卡、家庭頁、成員代墊頁永遠同色,不同人盡量不同色。
///
/// 顏色只由識別字串決定(沒有任何儲存的狀態),用 FNV-1a 而不是 `hashValue`:後者每次啟動結果都不同。
/// 全部是明確的 RGB(理由同 `AvatarPalette`):淺底配近黑字,淺色、深色模式共用同一組,對比都在 4.5:1 以上。
public enum MemberAvatarColor {
    public struct Swatch: Equatable, Sendable {
        public let fill: AvatarPalette.RGB
        public let letter: AvatarPalette.RGB
    }

    private static let letter = AvatarPalette.RGB(red: 31, green: 26, blue: 26)

    public static let swatches: [Swatch] = [
        (255, 156, 156), // 珊瑚
        (255, 190, 130), // 杏橘
        (240, 220, 120), // 檸檬黃
        (150, 220, 170), // 薄荷
        (120, 215, 215), // 青綠
        (140, 200, 245), // 天藍
        (180, 170, 245), // 靛紫
        (235, 160, 225), // 粉紫
    ].map { Swatch(fill: AvatarPalette.RGB(red: $0.0, green: $0.1, blue: $0.2), letter: letter) }

    /// 識別字串(使用者 ID;沒有 ID 時用名字)對應的色票編號。
    public static func index(for key: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash % UInt32(swatches.count))
    }

    public static func swatch(for key: String) -> Swatch { swatches[index(for: key)] }
}
