import SwiftUI

/// 鎖畫面(#298):不透明、蓋住整個 app,只有 App 名稱、鎖圖示與「解鎖」按鈕。出現時自動跳出系統的驗證;
/// 取消或失敗按「解鎖」可以再試。VoiceOver 念「已鎖定,需要 Face ID 解鎖」。
struct AppLockView: View {
    let model: AppLockModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("我的記帳本")
                .font(.title2.weight(.semibold))
            Text("已鎖定")
                .foregroundStyle(.secondary)
            if let message = model.failureMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("appLock.error")
            }
            Spacer()
            Button {
                Task { await model.unlock() }
            } label: {
                Text("使用 \(model.unlockMethodName) 解鎖")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ciFill)
            .disabled(model.state == .authenticating)
            .accessibilityIdentifier("appLock.unlock")
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 不透明的背景:背後的帳務完全看不到,不是半透明。
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("已鎖定,需要 \(model.unlockMethodName) 解鎖")
        .accessibilityIdentifier("appLock.screen")
        .task {
            await model.refreshCapability()
            await model.unlock()
        }
    }
}
