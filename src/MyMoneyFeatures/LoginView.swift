import SwiftUI

/// 登入頁(parity.md「登入」):登入與註冊都開系統的安全登入視窗(#334),這裡沒有帳密欄位。
/// 錯誤訊息放在 Section footer(DESIGN.md「元件對照」)。
struct LoginView: View {
    let model: LoginModel

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
                // web 的 passkey 在前端登入頁;原生 app 的登入頁就是這裡(parity.md,#339)。
                GlassCapsuleButton(title: "使用通行金鑰登入", systemImage: "person.badge.key") {
                    Task { await model.signInWithPasskey() }
                }
                .frame(maxWidth: .infinity)
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("login.passkey")
                .clearListRow()
            } footer: {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("login.error")
                }
            }

            Section {
                HStack(spacing: 4) {
                    Text("還沒有帳號？")
                        .foregroundStyle(.secondary)
                    Button("立即註冊") {
                        Task { await model.register() }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.ciText)
                    .fixedSize()
                    .disabled(model.isSubmitting)
                    .accessibilityIdentifier("login.register")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            // 錯誤出現在畫面下方，VoiceOver 使用者不一定會移過去，直接念出來。
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}
