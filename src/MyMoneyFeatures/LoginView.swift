import SwiftUI

/// 未登入的畫面(parity.md「登入」,#356):沒有 App 自己的登入頁，只是空白背景，登入在自動打開的系統登入視窗(#334)。
/// 關掉視窗會再開;其他錯誤才顯示說明與「重試」(空狀態樣式,DESIGN.md「元件對照」)。
struct LoginView: View {
    let model: LoginModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack {
            if let message = model.errorMessage {
                ContentUnavailableView {
                    Label("無法登入", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message).accessibilityIdentifier("login.error")
                } actions: {
                    PrimaryCapsuleButton(title: "重試") {
                        Task { await model.retry() }
                    }
                    .accessibilityIdentifier("login.retry")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        // 等 scene 進前景才開：冷啟動時太早開,系統登入視窗會開不起來(#351);離開前景時關掉的視窗等回來再開。
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await model.appeared() }
            } else {
                model.sceneLeftForeground()
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            // 錯誤出現時 VoiceOver 使用者不一定會移過去，直接念出來。
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}

/// 登入入口頁(#364、#367):主動登出後才出現(不論有沒有開 Face ID 登入;冷啟動也停在這裡),只有品牌與「登入」。
/// 按「登入」有保留的 session 就刷臉，沒有(或刷臉取消、失敗)就開登入網頁;登入網頁關掉回到這裡。
struct SignInEntryView: View {
    let signIn: () -> Void

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
                PrimaryCapsuleButton(title: "登入", fillsWidth: true, action: signIn)
                    .accessibilityIdentifier("login.entry")
                    .clearListRow()
            }
        }
    }
}
