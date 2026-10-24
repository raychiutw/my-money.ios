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
    private let appLock: AppLockModel
    @Environment(\.scenePhase) private var scenePhase

    public init(login: LoginModel, register: RegisterModel, signedIn: SignedInScreens, appLock: AppLockModel) {
        self.login = login
        self.register = register
        self.signedIn = signedIn
        self.appLock = appLock
    }

    public var body: some View {
        Group {
            if session.current == nil {
                NavigationStack {
                    LoginView(model: login, register: register)
                }
                // iPad:登入與註冊的欄位和按鈕限制在可讀寬度(#173)。
                .readableContentWidth()
            } else if let screens = signedIn.current {
                MainTabView(screens: screens)
            } else {
                ProgressView()
            }
        }
        // 鎖著時背後的內容對 VoiceOver 與點擊都不可及(只是蓋住畫面不夠:VoiceOver 仍讀得到、點得到後面的帳務)。
        .accessibilityHidden(appLock.isLocked)
        .allowsHitTesting(!appLock.isLocked)
        .onChange(of: session.current?.user.id, initial: true) {
            signedIn.update(for: session.current)
            // App 鎖(#298):讀回上次的 session(冷啟動)才一開始就鎖;剛登入成功不鎖;沒有 session 就沒有東西好鎖。
            if let user = session.current?.user.id {
                appLock.sessionStarted(userID: user, restored: session.didRestoreFromStorage)
            } else {
                appLock.sessionEnded()
            }
        }
        // 離開 app 滿寬限時間再回來才鎖(#298)。
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: appLock.enteredBackground()
            case .active: appLock.becameActive()
            default: break
            }
        }
        // 鎖畫面蓋在所有內容上(不透明),包含 sheet 之上的畫面由系統層級的 overlay 蓋住整個根畫面。
        .overlay {
            if appLock.isLocked {
                AppLockView(model: appLock)
                    .transition(.identity)
            }
        }
    }
}
