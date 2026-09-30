import SwiftUI

/// 「複製」按鈕：按下後把 `text` 複製到剪貼簿，按鈕短暫改成打勾和「已複製」(多久見 `copiedFeedbackDuration`)。
/// 綁定指令、邀請碼、Webhook 網址共用(#79)。
struct CopyButton: View {
    var title = "複製"
    var copiedTitle = "已複製"
    let text: String
    @Environment(\.copiedFeedbackDuration) private var copiedFeedbackDuration
    @State private var isCopied = false

    var body: some View {
        Button(isCopied ? copiedTitle : title, systemImage: isCopied ? "checkmark" : "doc.on.doc") {
            copyToPasteboard(text)
            isCopied = true
            Task {
                try? await Task.sleep(for: copiedFeedbackDuration)
                isCopied = false
            }
        }
    }
}
