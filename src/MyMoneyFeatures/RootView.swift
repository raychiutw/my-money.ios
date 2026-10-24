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
        // 鎖畫面與隱私遮罩在獨立的 window(App 層的 `AppLockWindowPresenter`,蓋得住 sheet 與 alert);
        // 這裡再讓背後的內容對 VoiceOver 與點擊都不可及(只是蓋住畫面不夠:VoiceOver 仍讀得到、點得到後面的帳務)。
        .accessibilityHidden(appLock.isLocked)
        .allowsHitTesting(!appLock.isLocked)
        .onChange(of: session.current?.user.id, initial: true) {
            signedIn.update(for: session.current)
            // App 鎖(#298):讀回上次的 session(冷啟動)才一開始就鎖;剛登入成功不鎖;沒有 session 就沒有東西好鎖。
            if let user = session.current?.user.id {
                appLock.sessionStarted(userID: user, restored: session.didRestoreFromStorage)
                Task { await appLock.evaluateOffer() }
            } else {
                appLock.sessionEnded(clearingSetting: !session.endedByExpiry, forgettingUser: session.endedByDeletion)
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
        // 第一次登入成功後詢問要不要開啟 Face ID(只問一次,#300)。
        .alert(
            "要開啟 \(appLock.unlockMethodName) 解鎖嗎？",
            isPresented: Binding(get: { appLock.shouldOfferEnabling }, set: { if !$0 { appLock.hideOffer() } })
        ) {
            Button("開啟") { Task { await appLock.answerOffer(enable: true) } }
            Button("暫時不要", role: .cancel) { Task { await appLock.answerOffer(enable: false) } }
        } message: {
            Text("開啟後，每次打開或離開超過一分鐘再回來都要驗證本人，保護你的帳務。之後可以到「我的」設定裡更改。")
        }
    }
}
