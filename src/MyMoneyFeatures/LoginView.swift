import SwiftUI

/// 登入頁(parity.md「登入」)。錯誤訊息放在 Section footer(DESIGN.md「元件對照」)。
struct LoginView: View {
    @Bindable var model: LoginModel
    let register: RegisterModel
    @FocusState private var focusedField: Field?
    @Environment(\.suggestsStrongPasswords) private var suggestsStrongPasswords

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
                LabeledContent("電子郵件") {
                    TextField("電子郵件", text: $model.email, prompt: Text(verbatim: "your@email.com"))
                        .textContentType(.username)
                        .emailKeyboard()
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityIdentifier("login.email")
                }
                .tapToFocus($focusedField, equals: .email)

                HStack {
                    LabeledContent("密碼") {
                        passwordField
                            // UI 測試關掉密碼管理:用 Return 登入後，系統偶爾彈出「要儲存密碼嗎？」蓋住畫面(見 `suggestsStrongPasswords`)。
                            .textContentType(suggestsStrongPasswords ? .password : .oneTimeCode)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .accessibilityIdentifier("login.password")
                    }
                    .tapToFocus($focusedField, equals: .password)

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
            } header: {
                Text("登入帳號")
            } footer: {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("login.error")
                }
            }

            Section {
                // 單色填滿的玻璃膠囊(#134):淺色黑底白字、深色白底黑字;停用時系統會淡化。
                PrimaryCapsuleButton(title: model.submitTitle, fillsWidth: true, action: submit)
                    .disabled(!model.canSubmit)
                    .accessibilityIdentifier("login.submit")
                    .clearListRow()
            }

            Section {
                HStack(spacing: 4) {
                    Text("還沒有帳號？")
                        .foregroundStyle(.secondary)
                    NavigationLink("立即註冊") {
                        RegisterView(model: register)
                    }
                    .foregroundStyle(Color.ciText)
                    .fixedSize()
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

    @ViewBuilder
    private var passwordField: some View {
        if model.isPasswordVisible {
            TextField("密碼", text: $model.password, prompt: Text("輸入密碼"))
        } else {
            SecureField("密碼", text: $model.password, prompt: Text("輸入密碼"))
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.submit() }
    }
}

