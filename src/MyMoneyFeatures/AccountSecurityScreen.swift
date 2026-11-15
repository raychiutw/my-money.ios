import MyMoneyDomain
import SwiftUI

/// 「我的」→ 帳號安全(#338,與 web 的設定頁對等):登入裝置、修改密碼。
/// passkey(#339)之後在最上面加自己的 `Section`,其他區塊不動。
struct AccountSecurityScreen: View {
    @Bindable var model: AccountSecurityModel
    @State private var pendingSignOut: LoginSession?
    @State private var isSignOutOthersConfirming = false
    @FocusState private var focusedField: PasswordField?

    private enum PasswordField: Hashable {
        case current, new
    }

    var body: some View {
        List {
            sessionsSection
            passwordSection
        }
        .skeletonTransition(value: model.isLoadingSessions)
        .navigationTitle("帳號安全")
        .inlineNavigationTitle()
        .task { await model.load() }
        .refreshable { await model.load() }
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
