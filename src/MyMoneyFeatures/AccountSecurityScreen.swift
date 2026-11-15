import MyMoneyDomain
import SwiftUI

/// 「我的」→ 帳號安全(#338、#339,與 web 的設定頁對等):通行金鑰、登入裝置、修改密碼。
struct AccountSecurityScreen: View {
    @Bindable var model: AccountSecurityModel
    let passkeys: PasskeysModel
    @State private var isNamingNewPasskey = false
    @State private var newPasskeyName = ""
    @State private var renamingPasskey: Passkey?
    @State private var renamedName = ""
    @State private var pendingPasskeyDeletion: Passkey?
    @State private var pendingSignOut: LoginSession?
    @State private var isSignOutOthersConfirming = false
    @FocusState private var focusedField: PasswordField?

    private enum PasswordField: Hashable {
        case current, new
    }

    var body: some View {
        List {
            passkeysSection
            sessionsSection
            passwordSection
        }
        .skeletonTransition(value: model.isLoadingSessions || passkeys.isLoading)
        .navigationTitle("帳號安全")
        .inlineNavigationTitle()
        .task { await model.load() }
        .task { await passkeys.load() }
        .refreshable {
            async let sessions: Void = model.load()
            await passkeys.load()
            await sessions
        }
        // 從列上的 ⋯ 或滑動觸發,沒有按鈕可以當錨點,用畫面層級的 alert(DESIGN.md「元件對照」)。
        .alert(
            "登出裝置",
            isPresented: Binding(get: { pendingSignOut != nil }, set: { if !$0 { pendingSignOut = nil } }),
            presenting: pendingSignOut
        ) { session in
            Button("登出", role: .destructive) {
                Task { await model.signOut(session) }
            }
            Button("取消", role: .cancel) {}
        } message: { session in
            Text(model.signOutConfirmation(for: session))
        }
        .errorAlert("無法登出裝置", message: model.alertMessage) { model.alertMessage = nil }
        .alert(
            "刪除通行金鑰",
            isPresented: Binding(get: { pendingPasskeyDeletion != nil }, set: { if !$0 { pendingPasskeyDeletion = nil } }),
            presenting: pendingPasskeyDeletion
        ) { passkey in
            Button("刪除", role: .destructive) {
                Task { await passkeys.delete(passkey) }
            }
            Button("取消", role: .cancel) {}
        } message: { passkey in
            Text(passkeys.deleteConfirmation(for: passkey))
        }
        .alert(
            "重新命名",
            isPresented: Binding(get: { renamingPasskey != nil }, set: { if !$0 { renamingPasskey = nil } }),
            presenting: renamingPasskey
        ) { passkey in
            TextField("名稱", text: $renamedName)
            Button("儲存") {
                Task { await passkeys.rename(passkey, to: renamedName) }
            }
            Button("取消", role: .cancel) {}
        }
        .errorAlert("通行金鑰", message: passkeys.alertMessage) { passkeys.alertMessage = nil }
    }

    /// 通行金鑰(passkey,#339):建立、改名、刪除。刪除只停用之後的登入,不登出已登入的裝置。
    private var passkeysSection: some View {
        Section {
            if passkeys.isLoading {
                SkeletonItemRow()
                    .skeletonRow()
            } else if let message = passkeys.errorMessage, passkeys.passkeys == nil {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                GlassCapsuleButton(title: "重試") {
                    Task { await passkeys.load() }
                }
            }
            ForEach(passkeys.passkeys ?? []) { passkey in
                PasskeyRow(passkey: passkey)
                    .trailingMoreMenu(label: "\(passkey.name)的更多動作", identifier: "security.passkey.more") {
                        Button("重新命名", systemImage: "pencil") {
                            renamedName = passkey.name
                            renamingPasskey = passkey
                        }
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            pendingPasskeyDeletion = passkey
                        }
                    }
                    .swipeActions {
                        DestructiveSwipeButton("刪除", systemImage: "trash") {
                            pendingPasskeyDeletion = passkey
                        }
                    }
            }
            if passkeys.passkeys != nil {
                Button {
                    newPasskeyName = ""
                    isNamingNewPasskey = true
                } label: {
                    ActionRowLabel(title: passkeys.isCreating ? "建立中…" : "建立通行金鑰", systemImage: "person.badge.key")
                }
                .disabled(passkeys.isCreating)
                .accessibilityIdentifier("security.createPasskey")
                // 名稱輸入掛在這顆按鈕上;留空由後端命名為「Passkey」。
                .alert("建立通行金鑰", isPresented: $isNamingNewPasskey) {
                    TextField("名稱", text: $newPasskeyName, prompt: Text("例如：我的 iPhone"))
                    Button("繼續") {
                        Task { await passkeys.create(name: newPasskeyName) }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("接著用 Face ID 或 Touch ID 建立，之後就能免密碼登入。")
                }
            }
        } header: {
            Text("通行金鑰")
        } footer: {
            Text("透過 iCloud 鑰匙圈同步，web 建立的通行金鑰也能在這台裝置登入。")
        }
    }

    private var sessionsSection: some View {
        Section("登入裝置") {
            if model.isLoadingSessions {
                SkeletonItemRow()
                    .skeletonAnnouncement()
                SkeletonItemRow()
                    .skeletonRow()
            } else if let message = model.sessionsErrorMessage, model.loginSessions == nil {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                GlassCapsuleButton(title: "重試") {
                    Task { await model.load() }
                }
            }
            ForEach(model.loginSessions ?? []) { session in
                LoginSessionRow(session: session)
                    .trailingMoreMenu(
                        label: "\(session.deviceName)的更多動作", identifier: "security.session.more",
                        isShown: !session.isCurrent
                    ) {
                        Button("登出", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            pendingSignOut = session
                        }
                    }
                    .swipeActions {
                        if !session.isCurrent {
                            DestructiveSwipeButton("登出", systemImage: "rectangle.portrait.and.arrow.right") {
                                pendingSignOut = session
                            }
                        }
                    }
            }
            if model.loginSessions != nil {
                Button(role: .destructive) {
                    isSignOutOthersConfirming = true
                } label: {
                    ActionRowLabel(title: "登出其他所有裝置", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(!model.hasOtherSessions)
                .accessibilityIdentifier("security.signOutOthers")
                // 確認訊息掛在這顆按鈕上(#169)。
                .confirmationDialog("登出其他所有裝置", isPresented: $isSignOutOthersConfirming, titleVisibility: .visible) {
                    Button("登出", role: .destructive) {
                        Task { await model.signOutOtherSessions() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("除了這台裝置，其他登入的裝置都需要重新登入。")
                }
            }
        }
    }

    private var passwordSection: some View {
        Section {
            // 欄位要有看得見的標籤,placeholder 只放範例或規則(DESIGN.md「列與欄位」第 8 條)。
            LabeledContent("目前密碼") {
                SecureField("目前密碼", text: $model.currentPassword, prompt: Text("必填"))
                    .textContentType(.password)
                    .focused($focusedField, equals: .current)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .new }
                    .accessibilityIdentifier("security.currentPassword")
            }
            .tapToFocus($focusedField, equals: .current)
            LabeledContent("新密碼") {
                SecureField("新密碼", text: $model.newPassword, prompt: Text("至少 \(AccountSecurityModel.minimumPasswordLength) 個字元"))
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .new)
                    .submitLabel(.done)
                    .accessibilityIdentifier("security.newPassword")
            }
            .tapToFocus($focusedField, equals: .new)
            Button {
                focusedField = nil
                Task { await model.changePassword() }
            } label: {
                ActionRowLabel(title: "修改密碼", systemImage: "key")
            }
            .disabled(!model.canChangePassword)
            .accessibilityIdentifier("security.changePassword")
        } header: {
            Text("修改密碼")
        } footer: {
            if let message = model.passwordErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("security.passwordError")
            } else if let message = model.passwordChangedMessage {
                Text(message)
                    .accessibilityIdentifier("security.passwordChanged")
            }
        }
    }
}

/// 一個通行金鑰:名稱,下面是最後使用與建立時間,台灣時間。
private struct PasskeyRow: View {
    let passkey: Passkey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(passkey.name)
            Group {
                Text(passkey.lastUsedAt.map { "最後使用 \(AccountSecurityModel.timeText($0))" } ?? "尚未使用")
                Text("建立於 \(AccountSecurityModel.timeText(passkey.createdAt))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("security.passkey")
    }
}

/// 一個登入工作階段:裝置名稱,下面每個欄位一行(這台裝置、最後使用、登入時間、client),台灣時間。
private struct LoginSessionRow: View {
    let session: LoginSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.deviceName)
            Group {
                if session.isCurrent {
                    Text("這台裝置")
                        .foregroundStyle(.primary)
                }
                Text("最後使用 \(AccountSecurityModel.timeText(session.lastUsedAt))")
                Text("登入於 \(AccountSecurityModel.timeText(session.createdAt))")
                Text(session.client)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(session.isCurrent ? "security.session.current" : "security.session")
    }
}
