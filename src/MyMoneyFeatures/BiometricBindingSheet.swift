import SwiftUI

/// 開啟 Face ID 登入時重新輸入帳密(#310):驗證成功且是目前登入的帳號才綁定並關閉。
struct BiometricBindingSheet: View {
    let settings: BiometricLoginSettings
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Bool
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("電子郵件") {
                        TextField("電子郵件", text: $email)
                            .textContentType(.username)
                            .emailKeyboard()
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("biometricBind.email")
                    }
                    LabeledContent("密碼") {
                        SecureField("密碼", text: $password, prompt: Text("輸入密碼"))
                            .textContentType(.oneTimeCode)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .accessibilityIdentifier("biometricBind.password")
                    }
                } header: {
                    Text("重新輸入帳號密碼")
                } footer: {
                    if let message = settings.errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("biometricBind.error")
                    } else {
                        Text("驗證成功後，帳號密碼只存在這支手機的 Keychain，之後登入可以直接用 \(settings.methodName)。")
                    }
                }
                Section {
                    PrimaryCapsuleButton(title: settings.isWorking ? "驗證中…" : "綁定", fillsWidth: true, action: submit)
                        .disabled(settings.isWorking || email.isEmpty || password.isEmpty)
                        .accessibilityIdentifier("biometricBind.submit")
                        .clearListRow()
                }
            }
            .navigationTitle("\(settings.methodName) 登入")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("biometricBind.close")
                }
            }
            .onAppear { email = settings.currentEmail }
            // 關掉表單就取消還沒完成的綁定,不會在背景偷偷存起來。
            .onDisappear { task?.cancel() }
        }
    }

    private func submit() {
        guard !settings.isWorking, !email.isEmpty, !password.isEmpty else { return }
        task = Task {
            if await settings.enable(email: email, password: password) { dismiss() }
        }
    }
}
