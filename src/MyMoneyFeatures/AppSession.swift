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

    @ObservationIgnored private let storage: any SessionStorage

    /// 讀回上次存下的 session:30 天內重開 app 直接進入 tab 外殼。
    /// 過期的 token 不在本機判斷，等後端回 401 時再回到登入頁(跟 web 一樣)。
    public init(storage: any SessionStorage) {
        self.storage = storage
        current = storage.load()
        didRestoreFromStorage = current != nil
    }

    /// 登入或註冊成功後開始 session,並存到裝置上。
    public func start(_ session: Session) {
        storage.save(session)
        didRestoreFromStorage = false
        current = session
    }

    /// 清掉 session、回到登入頁。登出不打 API,也不跳確認(跟 web 一樣)。
    public func signOut() {
        endedByExpiry = false
        endedByDeletion = false
        storage.clear()
        didRestoreFromStorage = false
        current = nil
    }
}

extension AppSession: SessionProvider {
    public func currentToken() async -> String? {
        current?.token
    }

    /// 帳號刪除成功之後:跟登出一樣清掉 session,並記下是刪除帳號。
    public func signOutAfterAccountDeletion() {
        signOut()
        endedByDeletion = true
    }

    /// 任何非 `/auth/*` 的請求回應 401 時，翻譯層會呼叫這裡：跟登出一樣清掉 session、回到登入頁。
    public func sessionDidExpire() async {
        signOut()
        endedByExpiry = true
    }
}
