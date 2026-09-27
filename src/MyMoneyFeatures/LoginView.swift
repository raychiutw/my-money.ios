import SwiftUI

/// 登入頁(parity.md「登入」)。錯誤訊息放在 Section footer(DESIGN.md「元件對照」)。
struct LoginView: View {
    @Bindable var model: LoginModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

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
                TextField("電子郵件", text: $model.email, prompt: Text(verbatim: "your@email.com"))
                    .textContentType(.username)
                    .emailKeyboard()
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityIdentifier("login.email")

                HStack {
                    passwordField
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .accessibilityIdentifier("login.password")

                    Button {
                        model.isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: model.isPasswordVisible ? "eye.slash" : "eye")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(model.isPasswordVisible ? "隱藏密碼" : "顯示密碼")
                    .accessibilityIdentifier("login.togglePassword")
                }
            } footer: {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("login.error")
                }
            }

            Section {
                Button(action: submit) {
                    Text(model.submitTitle)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("login.submit")
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            // 錯誤出現在畫面下方，VoiceOver 使用者不一定會移過去，直接念出來。
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if model.isPasswordVisible {
            TextField("密碼", text: $model.password)
        } else {
            SecureField("密碼", text: $model.password)
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.submit() }
    }
}

private extension View {
    /// Email 欄位的鍵盤：email 鍵盤、不自動大寫。只有 iOS 有這些設定(`swift test` 會在 macOS 上編譯)。
    func emailKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
