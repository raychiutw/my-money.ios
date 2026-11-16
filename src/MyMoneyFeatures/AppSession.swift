import MyMoneyDomain
import Observation

/// app 層級的登入狀態，用 `Environment` 往下傳。`current` 是 `nil` 時顯示登入頁，否則顯示 tab 外殼。
@MainActor
@Observable
public final class AppSession {
    /// 登入中的 session;未登入時是 `nil`。
    public private(set) var current: Session?

    /// 這個 session 是冷啟動時從裝置讀回來的(不是剛輸入密碼登入的);App 鎖只在這種情況下一開始就鎖(#298)。
    public private(set) var didRestoreFromStorage = false
    /// 上一次 session 結束是不是因為後端回 401(過期);主動登出與刪除帳號是 `false`。App 鎖只在主動結束時清掉設定(#299)。
    public private(set) var endedByExpiry = false
    /// 上一次 session 結束是不是因為刪除帳號(只有這種情況才清掉「已問過要不要開啟 App 鎖」的記號,#300)。
    public private(set) var endedByDeletion = false

    /// 這次 session 開始時已經刷過臉(冷啟動讀出受保護的 session,或剛完成綁定):App 鎖不再鎖、也不問(#358)。
    public private(set) var verifiedByBiometrics = false

    @ObservationIgnored private let storage: any SessionStorage

    /// 冷啟動時存著受生物辨識保護的 session(Face ID 登入的綁定,#357),還沒刷臉讀出來:
    /// 根畫面要呼叫 `unlockProtectedSession()`,這段期間不顯示登入頁。
    public private(set) var isUnlocking = false

    /// 讀回上次存下的 session:30 天內重開 app 直接進入 tab 外殼。讀回來只有更新權杖,
    /// 第一個請求由翻譯層先 refresh;更新權杖失效(`invalid_grant`)時才回到登入頁(#335)。
    /// 受生物辨識保護的 session 要等 `unlockProtectedSession()` 刷臉才讀得出來。
    public init(storage: any SessionStorage) {
        self.storage = storage
        if storage.storedProtection() == .biometric {
            isUnlocking = true
        } else {
            current = storage.load()
            didRestoreFromStorage = current != nil
        }
    }

    /// 冷啟動刷臉讀出受保護的 session:通過進入 tab 外殼;取消或失敗維持未登入(綁定留著，下次冷啟動再試);
    /// 保存已失效(臉部資料變更)就清掉。
    public func unlockProtectedSession() async {
        guard isUnlocking else { return }
        defer { isUnlocking = false }
        switch await storage.loadProtected(reason: Self.unlockReason) {
        case let .success(session):
            verifiedByBiometrics = true
            isBiometricSignInEnabled = true
            current = session
            didRestoreFromStorage = true
        case .invalidated:
            storage.clear()
        case .cancelled, .failed:
            break
        }
    }

    /// 系統登入視窗登入成功後開始 session。使用者按的是「用 Face ID 登入」時直接刷臉綁定(不詢問):
    /// 先存成受保護的再讀一次(讀取會跳刷臉),通過就留著;取消或失敗改用一般保存，照樣登入。
    public func start(_ result: SignInResult) async {
        guard result.biometric else { return start(result.session) }
        if await bind(result.session) {
            begin(result.session, verifiedByBiometrics: true)
        } else {
            begin(result.session)
        }
    }

    /// 登入或註冊成功後開始 session,並用一般保存存到裝置上(取代之前的綁定)。
    public func start(_ session: Session) {
        save(session)
        begin(session)
    }

    private func begin(_ session: Session, verifiedByBiometrics: Bool = false) {
        self.verifiedByBiometrics = verifiedByBiometrics
        endedByExpiry = false
        endedByDeletion = false
        didRestoreFromStorage = false
        current = session
    }

    /// 「我的」的「使用 Face ID 登入」開關:session 是否受生物辨識保護。
    public private(set) var isBiometricSignInEnabled = false

    /// 開啟或關閉 Face ID 登入(#358)。開啟:跟登入時綁定一樣，存成受保護的再讀一次(跳刷臉),通過才算開，
    /// 取消或失敗改回一般保存;關閉:改回一般保存，不刷臉、不登出。
    public func setBiometricSignIn(_ enabled: Bool) async {
        guard let current else { return }
        guard enabled else { return save(current) }
        _ = await bind(current)
    }

    /// 存成受保護的再讀一次(讀取會跳刷臉):通過回傳 `true`;否則改用一般保存。
    /// 刷臉期間 refresh 輪替過權杖就存最新的 session。
    private func bind(_ session: Session) async -> Bool {
        storage.save(session, protection: .biometric)
        if case .success = await storage.loadProtected(reason: Self.bindReason) {
            isBiometricSignInEnabled = true
            return true
        }
        save(self.current ?? session)
        return false
    }

    /// 一般保存。
    private func save(_ session: Session) {
        storage.save(session, protection: .standard)
        isBiometricSignInEnabled = false
    }

    private static let unlockReason = "登入「我的記帳本」"
    private static let bindReason = "以後打開「我的記帳本」直接用生物辨識登入"

    /// 清掉 session(兩種保存都清)、回到登入頁。登出不打 API,也不跳確認(跟 web 一樣)。
    public func signOut() {
        endedByExpiry = false
        endedByDeletion = false
        storage.clear()
        didRestoreFromStorage = false
        verifiedByBiometrics = false
        isBiometricSignInEnabled = false
        current = nil
    }
}

extension AppSession: SessionProvider {
    public func currentTokens() async -> SessionTokens? {
        current?.tokens
    }

    /// refresh 輪替後換成新的權杖並存回裝置;已經登出(refresh 進行中按了登出)就不理會,不會讓人重新登入;
    /// 登出後又登入了(目前的更新權杖不是這次送出的那個)也不理會,不會用舊 session 的權杖蓋掉新的。
    public func sessionDidRefresh(_ tokens: SessionTokens, replacing previousRefresh: String) async {
        guard let current, current.tokens.refresh == previousRefresh else { return }
        let refreshed = Session(user: current.user, tokens: tokens)
        storage.save(refreshed)
        self.current = refreshed
    }

    /// 帳號刪除成功之後:跟登出一樣清掉 session,並記下是刪除帳號。
    public func signOutAfterAccountDeletion() {
        signOut()
        endedByDeletion = true
    }

    /// 任何請求回應 401 且 `WWW-Authenticate` 含 `invalid_token` 時，翻譯層會呼叫這裡：跟登出一樣清掉 session、回到登入頁。
    public func sessionDidExpire() async {
        signOut()
        endedByExpiry = true
    }
}
