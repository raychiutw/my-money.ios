/// 把 session 存在裝置上，重開 app 時不用再登入(live 實作存在 Keychain,ADR-0012)。
///
/// 保存有兩種保護等級(#357):一般,或受生物辨識保護(Face ID 登入的綁定:讀取要通過目前錄好的臉)。
public protocol SessionStorage: Sendable {
    /// 存下的 session 用哪種保護等級;沒有存時是 `nil`。不會跳刷臉。
    func storedProtection() -> SessionProtection?

    /// 一般保存的 session;沒有存、或存的是受保護的(要用 `loadProtected`)時是 `nil`。不會跳刷臉。
    func load() -> Session?

    /// 讀受生物辨識保護的 session:系統會跳刷臉，讀完才回來(不阻塞 main thread)。
    /// - Parameter reason: 給人看的說明(Touch ID 的提示會顯示)。
    func loadProtected(reason: String) async -> ProtectedSessionLoad

    /// 存檔(先刪再寫),保留原本的保護等級(沒有存過就是一般):refresh 輪替寫入新權杖不需要刷臉。
    func save(_ session: Session)

    /// 用指定的保護等級存檔(先刪再寫,兩種保存只會留一份)。寫入不需要刷臉。
    func save(_ session: Session, protection: SessionProtection)

    /// 清掉兩種保存,連同「登出後保留」的記號。
    func clear()

    /// 「登出後保留」的記號(#364):Face ID 登入的人主動登出、受保護的 session 留在裝置上。
    /// 有記號時冷啟動停在登入入口頁、不自動刷臉。存在裝置上、跨冷啟動;不會跳刷臉。
    func isKeptAfterSignOut() -> Bool

    /// 設定或清掉「登出後保留」的記號;存檔(`save`)不會動到它。
    func setKeptAfterSignOut(_ kept: Bool)
}

/// session 保存的保護等級(#357)。
public enum SessionProtection: Sendable, Equatable {
    /// 裝置解鎖時就讀得到。
    case standard
    /// 受生物辨識保護:只認目前錄好的臉(或指紋),不接受裝置密碼;新增或更改臉部資料後失效。
    case biometric
}

/// 讀取受生物辨識保護的 session 的結果(#357)。
public enum ProtectedSessionLoad: Sendable, Equatable {
    case success(Session)
    /// 使用者(或系統)取消刷臉。
    case cancelled
    /// 刷臉沒通過，或其他讀取錯誤。
    case failed
    /// 保存已失效(臉部資料變更,或已經不在了):要重新登入。回傳前已清掉保存。
    case invalidated
}
