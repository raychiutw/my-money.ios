import MyMoneyAPI
import MyMoneyFeatures
import SwiftUI
#if DEBUG
// 只有 Debug 的 `-uiTesting` 會用到 in-memory repository;Release(TestFlight)不引用。
import MyMoneyTestSupport
#endif

/// 唯一的 composition root:依啟動參數組裝 live 依賴或 UI 測試用的 in-memory 依賴。
@main
struct MyMoneyApp: App {
    private let session: AppSession
    private let login: LoginModel
    private let register: RegisterModel

    init() {
        #if DEBUG
        // UI 測試不連網路：登入改用 in-memory repository。session 仍存在 Keychain
        // (另一個 service,不碰真的 session),才驗證得到「重開 app 直接進入 tab 外殼」。
        // 只在 Debug 生效,Release(TestFlight)不理會 -uiTesting。
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") {
            let storage = KeychainSessionStorage(service: "com.raychiu.mymoney.session.ui-testing")
            if arguments.contains("-resetSession") {
                storage.clear()
            }
            session = AppSession(storage: storage)
            let auth = InMemoryAuthRepository(members: [.sample])
            login = LoginModel(auth: auth, session: session)
            register = RegisterModel(auth: auth, session: session)
            return
        }
        #endif
        session = AppSession(storage: KeychainSessionStorage(service: "com.raychiu.mymoney.session"))
        // APIClient 透過 session 取得 token,並在非 /auth/* 的 401 時讓 session 回到登入頁。
        let client = APIClient(session: session)
        let auth = LiveAuthRepository(client: client)
        login = LoginModel(auth: auth, session: session)
        register = RegisterModel(auth: auth, session: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView(login: login, register: register)
                .environment(session)
        }
    }
}
