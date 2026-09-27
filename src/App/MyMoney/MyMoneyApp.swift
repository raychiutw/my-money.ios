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
    private let signedIn: SignedInScreens
    /// UI 測試關掉高強度密碼建議(見 `suggestsStrongPasswords`)。
    private let suggestsStrongPasswords: Bool

    init() {
        #if DEBUG
        // UI 測試不連網路：改用 in-memory repository。session 仍存在 Keychain
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
            let accounts = InMemoryAccountRepository.sample()
            signedIn = SignedInScreens {
                let dataVersion = DataVersion()
                return MainScreens(accounts: AccountsModel(repository: accounts, dataVersion: dataVersion))
            }
            suggestsStrongPasswords = false
            return
        }
        #endif
        session = AppSession(storage: KeychainSessionStorage(service: "com.raychiu.mymoney.session"))
        // APIClient 透過 session 取得 token,並在非 /auth/* 的 401 時讓 session 回到登入頁。
        let client = APIClient(session: session)
        let auth = LiveAuthRepository(client: client)
        login = LoginModel(auth: auth, session: session)
        register = RegisterModel(auth: auth, session: session)
        let accounts = LiveAccountRepository(client: client)
        // 登入後的畫面 model:每次有人登入時重建一份(見 `SignedInScreens`)。
        // 資料版本也是每個 session 一份，這個 session 的所有畫面共用。
        signedIn = SignedInScreens {
            let dataVersion = DataVersion()
            return MainScreens(accounts: AccountsModel(repository: accounts, dataVersion: dataVersion))
        }
        suggestsStrongPasswords = true
    }

    var body: some Scene {
        WindowGroup {
            RootView(login: login, register: register, signedIn: signedIn)
                .environment(session)
                .environment(\.suggestsStrongPasswords, suggestsStrongPasswords)
        }
    }
}
