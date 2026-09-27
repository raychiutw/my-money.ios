import SwiftUI

/// app 的根畫面：未登入時是全螢幕的登入頁，登入後是 tab 外殼(DESIGN.md「導覽」)。
///
/// 需要在 `Environment` 放入 `AppSession`。
public struct RootView: View {
    @Environment(AppSession.self) private var session
    private let login: LoginModel

    public init(login: LoginModel) {
        self.login = login
    }

    public var body: some View {
        if session.current == nil {
            LoginView(model: login)
        } else {
            MainTabView()
        }
    }
}
