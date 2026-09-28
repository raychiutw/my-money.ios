/// 把 session 存在裝置上，重開 app 時不用再登入(live 實作存在 Keychain)。
public protocol SessionStorage: Sendable {
    /// 上次存下的 session;沒有時是 `nil`。
    func load() -> Session?

    func save(_ session: Session)

    func clear()
}
