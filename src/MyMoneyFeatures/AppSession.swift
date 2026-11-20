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
    /// 綁定時查生物辨識種類，刷臉提示才寫得出 Face ID/Touch ID/Optic ID。
    @ObservationIgnored private let authenticator: (any DeviceAuthenticator)?
    /// 每次開始或結束 session 加一(refresh 輪替不算):刷臉回來時用它判斷 session 是否還是同一個。
    @ObservationIgnored private var generation = 0

    /// 冷啟動時存著受生物辨識保護的 session(Face ID 登入的綁定,#357),還沒刷臉讀出來:
    /// 根畫面要呼叫 `unlockProtectedSession()`,這段期間不顯示登入頁。
    public private(set) var isUnlocking = false

    /// 顯示登入入口頁(#364):Face ID 登入的人主動登出後，只有品牌與「登入」;冷啟動也停在這裡、不自動刷臉。
    public private(set) var showsSignInEntry = false

    /// 刷臉讀出、正在換新權杖的 session(#365):還沒進首頁，翻譯層 refresh 用它的權杖。
    @ObservationIgnored private var unlockingSession: Session?

    /// 登出時保留的 session(只放記憶體):登出前送出的 refresh 晚回來時，把保留的換成輪替後的權杖。
    @ObservationIgnored private var keptSession: Session?

    /// 讀回上次存下的 session:30 天內重開 app 直接進入 tab 外殼。讀回來只有更新權杖,
    /// 第一個請求由翻譯層先 refresh;更新權杖失效(`invalid_grant`)時才回到登入頁(#335)。
    /// 受生物辨識保護的 session 要等 `unlockProtectedSession()` 刷臉才讀得出來。
    public init(storage: any SessionStorage, authenticator: (any DeviceAuthenticator)? = nil) {
        self.storage = storage
        self.authenticator = authenticator
        if storage.storedProtection() == .biometric {
            // 主動登出後停在入口頁，等使用者按「登入」才刷臉;只是關掉 App 的冷啟動直接刷臉。
            if storage.keptAfterSignOut() != nil {
                showsSignInEntry = true
            } else {
                isUnlocking = true
            }
        } else {
            current = storage.load()
            didRestoreFromStorage = current != nil
        }
    }

    /// 刷臉讀出受保護的 session(冷啟動或登入入口頁按「登入」):通過後先用 `auth` 換新權杖(#365),換新完成前維持解鎖中;
    /// 換新成功或網路錯誤等失敗進入 tab 外殼;更新權杖被伺服器拒絕就清掉保存、不進首頁,直接開登入網頁。
    /// 取消或失敗維持未登入(綁定留著，下次冷啟動再試);保存已失效(臉部資料變更)就清掉。
    public func unlockProtectedSession(refreshingWith auth: any AuthRepository) async {
        guard isUnlocking else { return }
        defer { isUnlocking = false }
        switch await storage.loadProtected(reason: Self.unlockReason) {
        case let .success(session):
            // 換新期間還沒進首頁(`current` 是 nil):權杖由 `unlockingSession` 提供給翻譯層,
            // 輪替與失效都經過 `SessionProvider`,跟一般請求的 refresh 同一套。
            unlockingSession = session
            // 失敗不用在這裡處理:失效已由 `sessionDidExpire` 清掉 `unlockingSession`,其他錯誤照樣進首頁。
            try? await auth.refreshSession()
            guard let unlocked = unlockingSession else { return }
            unlockingSession = nil
            isBiometricSignInEnabled = true
            begin(unlocked, verifiedByBiometrics: true, restoredFromStorage: true)
        case .invalidated, .cancelled, .failed:
            // 失效時保存(連同 DPoP 金鑰)已由 `loadProtected` 清掉。
            break
        }
    }

    /// 登入入口頁按「登入」:有保留的 session 就刷臉(根畫面跟冷啟動一樣呼叫 `unlockProtectedSession()`;
    /// 取消或失敗就未登入、開登入網頁，保留的先不刪);沒有就直接開登入網頁。
    public func signInFromEntry() {
        showsSignInEntry = false
        isUnlocking = storage.storedProtection() == .biometric
    }

    /// 系統登入視窗登入成功後開始 session。使用者按的是「用 Face ID 登入」時直接刷臉綁定(不詢問):
    /// 先存成受保護的再讀一次(讀取會跳刷臉),通過就留著;取消或失敗改用一般保存，照樣登入。
    public func start(_ result: SignInResult) async {
        guard result.biometric else { return start(result.session) }
        let generation = self.generation
        let bound = await bind(result.session)
        // 刷臉期間登出了:不登入。
        guard generation == self.generation else { return }
        if bound {
            begin(result.session, verifiedByBiometrics: true)
        } else {
            begin(result.session)
        }
    }

    /// 登入或註冊成功後開始 session,存到裝置上:裝置上受保護的 session(不論是否登出保留,#364)是同一個人就換新、
    /// 維持受保護(寫入不需刷臉,Face ID 登入維持開啟);其他情況用一般保存,取代之前的(不同帳號就清掉前一個人的)。
    public func start(_ session: Session) {
        if storage.storedProtection() == .biometric, storage.storedUser() == session.user.id {
            storage.save(session, protection: .biometric)
            isBiometricSignInEnabled = true
        } else {
            save(session)
        }
        begin(session)
    }

    /// 開始新的 session:保存已經換成這次登入的(同帳號換新、不同帳號取代前一個人的),「登出後保留」的記號不再適用。
    private func begin(_ session: Session, verifiedByBiometrics: Bool = false, restoredFromStorage: Bool = false) {
        storage.setKeptAfterSignOut(nil)
        keptSession = nil
        showsSignInEntry = false
        generation += 1
        self.verifiedByBiometrics = verifiedByBiometrics
        endedByExpiry = false
        endedByDeletion = false
        didRestoreFromStorage = restoredFromStorage
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
    /// 刷臉期間 refresh 輪替過權杖就存最新的 session;登出、過期或換人了就不動保存(已經是別的 session 的)。
    private func bind(_ session: Session) async -> Bool {
        let generation = self.generation
        let name = await authenticator?.capability().biometryName ?? "Face ID"
        storage.save(session, protection: .biometric)
        let result = await storage.loadProtected(reason: "以後打開「我的記帳本」直接用 \(name) 登入")
        guard generation == self.generation else { return false }
        if case .success = result {
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

    /// 主動登出的結果:呼叫端依此決定要不要撤銷伺服器端的登入工作階段。
    public enum UserSignOut: Equatable, Sendable {
        /// Face ID 登入的人:session(連同 DPoP 金鑰)保留在裝置上,不撤銷。
        case keptForFaceID
        /// 其他人:全部清掉,要撤銷。
        case cleared
    }

    /// 主動登出(#364)。Face ID 登入(受保護的保存)的人保留 session、記下「登出後保留」、顯示登入入口頁;
    /// 其他人跟 `signOut()` 一樣全部清掉。
    public func signOutByUser() -> UserSignOut {
        guard let current, storage.storedProtection() == .biometric else {
            signOut()
            return .cleared
        }
        end()
        storage.setKeptAfterSignOut(current.user.id)
        keptSession = current
        showsSignInEntry = true
        return .keptForFaceID
    }

    /// 清掉 session(兩種保存與「登出後保留」的記號都清)、開登入網頁。用於刪除帳號、session 失效與一般登出。
    public func signOut() {
        storage.clear()
        keptSession = nil
        showsSignInEntry = false
        end()
    }

    /// 結束目前的 session(不動保存)。
    private func end() {
        endedByExpiry = false
        endedByDeletion = false
        didRestoreFromStorage = false
        verifiedByBiometrics = false
        isBiometricSignInEnabled = false
        generation += 1
        current = nil
    }
}

extension AppSession: SessionProvider {
    public func currentTokens() async -> SessionTokens? {
        activeSession?.tokens
    }

    /// refresh 輪替後換成新的權杖並存回裝置(刷臉後換新也是,#365);已經登出(refresh 進行中按了登出)就不理會,不會讓人重新登入;
    /// 登出後又登入了(目前的更新權杖不是這次送出的那個)也不理會,不會用舊 session 的權杖蓋掉新的。
    /// 登出時保留的 session 送出的 refresh 晚回來:保留的換成新的權杖(舊的已輪替作廢),不刷臉(#364)。
    public func sessionDidRefresh(_ tokens: SessionTokens, replacing previousRefresh: String) async {
        guard let matched = holder(of: previousRefresh) else { return }
        let refreshed = Session(user: matched.session.user, tokens: tokens)
        // 存回時維持原本的保護等級;刷臉後換新(#365)進首頁時用新的。
        storage.save(refreshed)
        switch matched.holder {
        case .current: current = refreshed
        case .unlocking: unlockingSession = refreshed
        case .kept: keptSession = refreshed
        }
    }

    /// 帳號刪除成功之後:跟登出一樣清掉 session,並記下是刪除帳號。
    public func signOutAfterAccountDeletion() {
        signOut()
        endedByDeletion = true
    }

    /// 任何請求回應 401 且 `WWW-Authenticate` 含 `invalid_token` 時，翻譯層會呼叫這裡：跟登出一樣清掉 session、回到登入頁。
    /// 刷臉後換新被拒(#365)時清掉保存、不進首頁。
    /// 只處理目前的 session:送出後已經登出(含保留的,#364)或換人,晚到的 401 不理會。
    public func sessionDidExpire(refresh: String) async -> Bool {
        switch holder(of: refresh)?.holder {
        case .unlocking:
            // 刷臉後換新被拒(#365):清掉保存(連同登出保留的記號)、不進首頁;回傳 true 讓翻譯層刪 DPoP 金鑰。
            unlockingSession = nil
            storage.clear()
            keptSession = nil
            showsSignInEntry = false
            return true
        case .current:
            signOut()
            endedByExpiry = true
            return true
        case .kept, nil:
            return false
        }
    }

    /// 持有更新權杖的是哪一份 session。
    private enum TokenHolder {
        /// 已進首頁的 session。
        case current
        /// 刷臉讀出、正在換新的 session(#365)。
        case unlocking
        /// 登出時保留的 session(#364)。
        case kept
    }

    /// 翻譯層送請求與 refresh 用的 session:進首頁後是目前的，刷臉後換新期間是解鎖中的(#365)。
    private var activeSession: Session? {
        current ?? unlockingSession
    }

    /// 這個更新權杖屬於哪一份 session:進首頁後只認目前的;還沒進首頁時，解鎖中的優先，其次是登出時保留的。
    /// 都不是(已經登出、換人或輪替過)就是 `nil`,晚回來的結果不理會。
    private func holder(of refresh: String) -> (holder: TokenHolder, session: Session)? {
        if let current {
            return current.tokens.refresh == refresh ? (.current, current) : nil
        }
        if let unlockingSession, unlockingSession.tokens.refresh == refresh {
            return (.unlocking, unlockingSession)
        }
        if let keptSession, keptSession.tokens.refresh == refresh {
            return (.kept, keptSession)
        }
        return nil
    }
}
