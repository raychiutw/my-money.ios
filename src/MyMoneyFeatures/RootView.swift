import SwiftUI

/// app 的根畫面：未登入時是全螢幕的登入頁(可以 push 到註冊頁),登入後是 tab 外殼(DESIGN.md「導覽」)。
///
/// 登入後的畫面 model 由 `SignedInScreens` 跟著 session 建立，換人登入時不會看到上一個人的資料。
/// 需要在 `Environment` 放入 `AppSession` 和 `AppearanceSetting`(「我的」的外觀設定)。
public struct RootView: View {
    @Environment(AppSession.self) private var session
    private let login: LoginModel
    private let register: RegisterModel
    private let signedIn: SignedInScreens

    public init(login: LoginModel, register: RegisterModel, signedIn: SignedInScreens) {
        self.login = login
        self.register = register
        self.signedIn = signedIn
    }

    public var body: some View {
        Group {
            if session.current == nil {
                NavigationStack {
                    LoginView(model: login, register: register)
                }
            } else if let screens = signedIn.current {
                MainTabView(screens: screens)
            } else {
                ProgressView()
            }
        }
        .onChange(of: session.current?.user.id, initial: true) {
            signedIn.update(for: session.current)
        }
    }
}
