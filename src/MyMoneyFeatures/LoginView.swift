import SwiftUI

/// 登入頁(parity.md「登入」):登入與註冊都在系統的安全登入視窗(#334),這裡只有品牌名稱與「登入」(#348)。
/// 錯誤訊息放在 Section footer(DESIGN.md「元件對照」)。
struct LoginView: View {
    let model: LoginModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Text("我的記帳本")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.tint)
                        .accessibilityAddTraits(.isHeader)
                    Text("家庭財務，輕鬆掌握")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                // 單色填滿的玻璃膠囊(#134):淺色黑底白字、深色白底黑字;停用時系統會淡化。
                PrimaryCapsuleButton(title: model.isSubmitting ? "登入中…" : "登入", fillsWidth: true) {
                    Task { await model.signIn() }
                }
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("login.submit")
                .clearListRow()
            } footer: {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("login.error")
                }
            }
        }
        // 登入頁一出現就開系統登入視窗(#348);關掉後留在這裡,按「登入」再開。
        // 等 scene 進前景才開：冷啟動時太早開,系統登入視窗會開不起來(#351)。
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await model.appeared() } }
        }
        .onChange(of: model.errorMessage) { _, message in
            // 錯誤出現在畫面下方，VoiceOver 使用者不一定會移過去，直接念出來。
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}
