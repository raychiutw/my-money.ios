import MyMoneyAPI
import MyMoneyFeatures
import SwiftUI
import UIKit
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
    /// 「我的」的外觀設定，套到整個 app(包含登入頁、sheet 和 alert)。
    private let appearance: AppearanceSetting
    /// UI 測試關掉高強度密碼建議(見 `suggestsStrongPasswords`)。
    private let suggestsStrongPasswords: Bool
    /// UI 測試拉長「已複製」的顯示時間(見 `copiedFeedbackDuration`);`nil` 是沿用預設值。
    ///
    /// 不要在 `init()` 建立 `EnvironmentValues()` 來取預設值：這麼早建立會讓整個 app 的
    /// accent 色變回系統藍(TestFlight 1.0 (36381212551) 的標題、按鈕都是藍的)。
    private let copiedFeedbackOverride: Duration?
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        #if DEBUG
        // UI 測試不連網路：改用 in-memory repository。session 仍存在 Keychain
        // (另一個 service,不碰真的 session),才驗證得到「重開 app 直接進入 tab 外殼」。
        // 只在 Debug 生效,Release(TestFlight)不理會 -uiTesting。
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") {
            let storage = KeychainSessionStorage(service: "com.raychiu.mymoney.session.ui-testing")
            // 總覽選過的視角、外觀也另外存，每個 UI 測試從預設值開始。
            let defaultsSuite = "com.raychiu.mymoney.ui-testing"
            let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
            if arguments.contains("-resetSession") {
                storage.clear()
                defaults.removePersistentDomain(forName: defaultsSuite)
            }
            session = AppSession(storage: storage)
            appearance = AppearanceSetting(defaults: defaults)
            let auth = InMemoryAuthRepository(members: [.sample])
            login = LoginModel(auth: auth, session: session)
            register = RegisterModel(auth: auth, session: session)
            let accounts = InMemoryAccountRepository.sample()
            let transactions = InMemoryTransactionRepository(transactions: SampleTransactions.makeForToday(includeFamilyEntries: arguments.contains("-uiTestingFamilyEntries")))
            let recurring = InMemoryRecurringRepository.sample()
            let goals = InMemorySavingsGoalRepository.sample()
            // 截圖巡覽要看 16 種分類的圓餅圖，其他 UI 測試用預設的 3 種。
            let statistics = arguments.contains("-uiTestingManyCategories")
                ? InMemoryStatisticsRepository.sampleWithEveryCategoryForToday(transactions: transactions)
                : InMemoryStatisticsRepository.sampleForToday(transactions: transactions)
            // 截圖巡覽要看走勢圖跨過零線的紅色段落，其他 UI 測試用不透支的預設範例。
            let forecast = arguments.contains("-uiTestingOverdraftForecast")
                ? InMemoryForecastRepository.overdraftSampleForToday()
                : InMemoryForecastRepository.sampleForToday()
            // 建立家庭之後，範例帳號有一筆用個人現金錢包墊付的晚餐 250,小美待報銷 600(撥款報銷的 UI 測試)。
            let advances = [InMemoryHouseholdRepository.myPendingAdvance, InMemoryHouseholdRepository.meiPendingAdvance]
            // 截圖巡覽要看已加入家庭的畫面，又不能在大字級打字建立家庭:啟動時就已加入(巡覽再用「離開家庭」拍建立與加入)。
            // `-uiTestingMemberRole`:範例帳號是一般成員(小美才是家庭管理員)，驗證邀請與撥款報銷的權限防呆(#132)。
            let household = arguments.contains("-uiTestingJoinedHousehold") || arguments.contains("-uiTestingMemberRole")
                ? InMemoryHouseholdRepository.sample(
                    myRole: arguments.contains("-uiTestingMemberRole") ? .member : .admin, advances: advances
                )
                : InMemoryHouseholdRepository(household: nil, advances: advances)
            let bot = InMemoryBotRepository.sample()
            signedIn = SignedInScreens { user in
                MainScreens(
                    currentUser: user.id,
                    accountRepository: accounts, transactionRepository: transactions, recurringRepository: recurring,
                    savingsGoalRepository: goals, statisticsRepository: statistics, forecastRepository: forecast,
                    householdRepository: household, botRepository: bot, defaults: defaults
                )
            }
            suggestsStrongPasswords = false
            copiedFeedbackOverride = .seconds(30)
            return
        }
        #endif
        session = AppSession(storage: KeychainSessionStorage(service: "com.raychiu.mymoney.session"))
        appearance = AppearanceSetting(defaults: .standard)
        // APIClient 透過 session 取得 token,並在非 /auth/* 的 401 時讓 session 回到登入頁。
        let client = APIClient(session: session)
        let auth = LiveAuthRepository(client: client)
        login = LoginModel(auth: auth, session: session)
        register = RegisterModel(auth: auth, session: session)
        let accounts = LiveAccountRepository(client: client)
        let transactions = LiveTransactionRepository(client: client)
        let recurring = LiveRecurringRepository(client: client)
        let goals = LiveSavingsGoalRepository(client: client)
        let statistics = LiveStatisticsRepository(client: client)
        let forecast = LiveForecastRepository(client: client)
        let household = LiveHouseholdRepository(client: client)
        let bot = LiveBotRepository(client: client)
        // 登入後的畫面 model:每次有人登入時重建一份(見 `SignedInScreens`),
        // 資料版本也是每個 session 一份，這個 session 的所有畫面共用。
        signedIn = SignedInScreens { user in
            MainScreens(
                currentUser: user.id,
                accountRepository: accounts, transactionRepository: transactions, recurringRepository: recurring,
                savingsGoalRepository: goals, statisticsRepository: statistics, forecastRepository: forecast,
                householdRepository: household, botRepository: bot
            )
        }
        suggestsStrongPasswords = true
        copiedFeedbackOverride = nil
    }

    var body: some Scene {
        WindowGroup {
            RootView(login: login, register: register, signedIn: signedIn)
                .environment(session)
                .environment(appearance)
                .environment(\.appVersion, AppVersion(infoDictionary: Bundle.main.infoDictionary))
                .environment(\.suggestsStrongPasswords, suggestsStrongPasswords)
                .transformEnvironment(\.copiedFeedbackDuration) { duration in
                    if let copiedFeedbackOverride { duration = copiedFeedbackOverride }
                }
                .onChange(of: appearance.appearance, initial: true) { _, selected in
                    Self.apply(selected)
                }
        }
    }

    /// 把外觀設在每個 window 上，登入頁、sheet 和 alert 都在 window 裡，一起跟著變。
    ///
    /// 不用 `preferredColorScheme`:在 iOS 27 上，「我的」開著時切到深色，之後再切成淺色或跟隨系統，
    /// sheet 都停在深色(#62 的截圖驗證)。window 的 `.unspecified` 就是跟隨系統，系統依時間自動切換也會跟著變;
    /// 增強對比是另一個 trait,不受影響。
    private static func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

/// 設定 UIKit appearance。要等 app 啟動完才設：在 `App.init()` 碰 UIKit,accent 色會變回系統藍
/// (`BrandColorUITests` 會失敗),跟 `EnvironmentValues()` 同一個雷。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 分段控制的字預設是 13pt(footnote 的大小),跟其他小字一樣往上一級到 subheadline(#43)。
        // ponytail: 啟動時取一次 Dynamic Type 的大小，執行中改字級要重開 app 才會跟著變。
        // 上限 21pt(subheadline 在 xxxLarge 的大小):分段控制的高度固定，無障礙字級時字會超出控制項、上緣被切掉(#78,AX5 截圖)。
        let font = UIFont.systemFont(ofSize: min(UIFont.preferredFont(forTextStyle: .subheadline).pointSize, 21))
        UISegmentedControl.appearance().setTitleTextAttributes([.font: font], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)],
            for: .selected
        )
        return true
    }
}
