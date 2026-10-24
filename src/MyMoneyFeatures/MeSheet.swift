import MyMoneyDomain
import SwiftUI

/// 「我的」sheet:姓名與 email,下面只有設定:機器人記帳、外觀(三列打勾)、登出、版本(ADR-0004、CONTEXT.md)。
/// 週期收支、儲蓄目標、現金流預測原本在「規劃」分頁,#178 起搬到總覽的功能入口。
struct MeSheet: View {
    let screens: MainScreens
    @Environment(AppSession.self) private var session
    @Environment(AppearanceSetting.self) private var appearanceSetting
    @Environment(AccountDeletionModel.self) private var deletion
    @Environment(AppLockModel.self) private var appLock
    @State private var isDeleteConfirming = false
    @Environment(\.appVersion) private var appVersion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appearance = appearanceSetting
        NavigationStack {
            List {
                if let user = session.current?.user {
                    header(of: user)
                }
                settings(appearance: $appearance.appearance)
            }
            .navigationTitle("我的")
            .inlineNavigationTitle()
            .errorAlert("無法刪除帳號", message: deletion.errorMessage) { deletion.clearError() }
            .toolbar {
                // 不放 `.confirmationAction`:iOS 26 會把它畫成 accent 填滿的主要動作鈕(ADR-0008)。
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("me.close")
                }
            }
        }
    }

    /// 頭像、姓名(`headline`)、email(`subheadline`)。頭像上的字是裝飾，VoiceOver 只念姓名與 email。
    private func header(of user: User) -> some View {
        Section {
            VStack(spacing: 4) {
                AvatarView(initial: AvatarInitial.text(for: user.name), baseSize: 72, font: .title.weight(.semibold), relativeTo: .title)
                    .accessibilityHidden(true)
                VStack(spacing: 2) {
                    Text(user.name)
                        .font(.headline)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func settings(appearance: Binding<Appearance>) -> some View {
        Section {
            // UI 測試用 identifier 找入口，不依賴文字。
            NavigationLink("機器人記帳") {
                BotScreen(model: screens.bot)
            }
            .accessibilityIdentifier("me.bot")
        }

        // 三列打勾，點一下就生效;字級是 body,不縮小(ADR-0004)。
        Section("外觀") {
            InlineChoiceRows(Appearance.allCases.map { ($0, $0.title) }, selection: appearance)
        }

        // App 鎖(#299):開啟與關閉都要先驗證成功一次。裝置沒有生物辨識也沒有密碼時停用並說明。
        Section {
            Toggle(
                "使用 \(appLock.unlockMethodName) 解鎖",
                isOn: Binding(
                    get: { appLock.isEnabled },
                    set: { newValue in Task { await appLock.requestEnabled(newValue) } }
                )
            )
            .tint(Color.ciFill)
            .disabled(!appLock.canEnable && !appLock.isEnabled)
            .accessibilityIdentifier("me.appLock")
        } footer: {
            if let message = appLock.settingMessage {
                Text(message)
            } else if !appLock.canEnable {
                Text("這支手機還沒有設定 Face ID 或裝置密碼,請先到「設定」開啟。")
            }
        }
        .task { await appLock.refreshCapability() }

        Section {
            // 登出不跳確認、不打 API(parity.md「全域」)。
            Button("登出", role: .destructive) {
                session.signOut()
            }
            .accessibilityIdentifier("me.signOut")
        }

        // 刪除帳號(#250,偏離 parity):破壞性、無法復原，放最下面並先確認;確認訊息掛在這顆按鈕上(#169)。
        Section {
            Button("刪除帳號", role: .destructive) {
                isDeleteConfirming = true
            }
            .disabled(deletion.isDeleting)
            .accessibilityIdentifier("me.deleteAccount")
            .confirmationDialog("刪除帳號", isPresented: $isDeleteConfirming, titleVisibility: .visible) {
                Button("刪除", role: .destructive) {
                    Task { await deletion.delete() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(deletion.confirmation)
            }
        } footer: {
            Text(appVersion.text)
                .frame(maxWidth: .infinity)
        }
    }
}
