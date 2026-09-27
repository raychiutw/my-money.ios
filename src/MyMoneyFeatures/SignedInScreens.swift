import MyMoneyDomain
import Observation

/// 登入後各個 tab 的畫面 model。由 composition root 建立。
@MainActor
public struct MainScreens {
    public let accounts: AccountsModel

    public init(accounts: AccountsModel) {
        self.accounts = accounts
    }
}

/// 讓登入後的畫面 model 跟著 session 建立：換了一個人就重建，登出就丟掉。
@MainActor
@Observable
public final class SignedInScreens {
    public private(set) var current: MainScreens?

    @ObservationIgnored private let make: @MainActor () -> MainScreens
    @ObservationIgnored private var userID: UserID?

    public init(make: @escaping @MainActor () -> MainScreens) {
        self.make = make
    }

    /// 同一個人時沿用現有的畫面;換人或登出時重建或丟掉，避免在共用的裝置上看到上一個人的資料。
    public func update(for session: Session?) {
        guard session?.user.id != userID else { return }
        userID = session?.user.id
        current = session == nil ? nil : make()
    }
}
