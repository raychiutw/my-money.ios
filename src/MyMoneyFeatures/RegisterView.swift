import SwiftUI

/// 註冊頁(parity.md「註冊」)。從登入頁 push 進來;錯誤訊息放在 Section footer(DESIGN.md「元件對照」)。
struct RegisterView: View {
    @Bindable var model: RegisterModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.suggestsStrongPasswords) private var suggestsStrongPasswords
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case email
        case password
        case confirmation
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Text("建立帳號")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.tint)
                        .accessibilityAddTraits(.isHeader)
                    Text("開始記錄你的財務生活")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("姓名", text: $model.name, prompt: Text("家庭成員名稱"))
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
                    .accessibilityIdentifier("register.name")

                TextField("電子郵件", text: $model.email, prompt: Text(verbatim: "your@email.com"))
                    .textContentType(.username)
                    .emailKeyboard()
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .accessibilityIdentifier("register.email")

                SecureField("密碼", text: $model.password, prompt: Text("至少 6 個字元"))
                    .textContentType(suggestsStrongPasswords ? .newPassword : nil)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmation }
                    .accessibilityIdentifier("register.password")

                SecureField("確認密碼", text: $model.confirmation, prompt: Text("再輸入一次密碼"))
                    .textContentType(suggestsStrongPasswords ? .newPassword : nil)
                    .focused($focusedField, equals: .confirmation)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .accessibilityIdentifier("register.confirmation")
            } footer: {
                if let message = model.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("register.error")
                }
            }

            Section {
                Button(action: submit) {
                    Text(model.submitTitle)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("register.submit")
            }

            Section {
                HStack(spacing: 4) {
                    Text("已有帳號？")
                        .foregroundStyle(.secondary)
                    Button("登入") {
                        dismiss()
                    }
                    .accessibilityIdentifier("register.backToLogin")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("建立帳號")
        .inlineNavigationTitle()
        .onChange(of: model.errorMessage) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private func submit() {
        guard model.canSubmit else { return }
        Task { await model.submit() }
    }
}
