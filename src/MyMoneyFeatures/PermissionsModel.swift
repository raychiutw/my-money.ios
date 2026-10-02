import Foundation
import MyMoneyDomain
import Observation

/// 登入的人的編輯權限(上游 ADR 0013、#133):帳戶頁、交易頁、信用卡詳細頁共用同一份，由 composition root 建立。
///
/// 角色(家庭管理員、一般成員)只問後端一次(`GET /households/current`)，不像 web 每頁問一次;
/// 家庭頁載入、建立、加入、離開之後用 `update` 同步。取得失敗時角色是 `nil`(家庭管理員才有的入口先不顯示)，
/// 下一次還會再問;後端永遠是最後一道防線(403)。
@MainActor
@Observable
public final class PermissionsModel {
    public private(set) var current: EditingPermissions

    @ObservationIgnored private let households: (any HouseholdRepository)?
    @ObservationIgnored private var isLoaded: Bool

    /// `role` 是已經知道的角色(沒有 `households` 時就以它為準，例如測試);有 `households` 時，要呼叫 `loadIfNeeded` 才會取得。
    public init(userID: UserID?, role: HouseholdRole? = nil, households: (any HouseholdRepository)? = nil) {
        current = EditingPermissions(userID: userID, role: role)
        self.households = households
        isLoaded = households == nil
    }

    /// 還沒取得過角色才問後端;取得失敗不算取得過。
    public func loadIfNeeded() async {
        guard !isLoaded, let households else { return }
        // 沒有家庭是正常的「沒有角色」;只有請求失敗才不算取得過。
        do {
            update(role: try await households.current()?.myRole)
        } catch {}
    }

    /// 同步角色(家庭頁載入、建立、加入、離開之後)。
    public func update(role: HouseholdRole?) {
        current = EditingPermissions(userID: current.userID, role: role)
        isLoaded = true
    }
}
