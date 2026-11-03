import Foundation
import MyMoneyDomain
import Observation

/// 「我的」→ 刪除帳號(#250)。web 沒有這個功能,後端從 `79edd20` 起有 `DELETE /auth/account`;
/// 使用者決定偏離 parity 加上(parity.md 刻意偏離、ADR-0001 補充)。成功後跟登出一樣回到登入頁。
@MainActor
@Observable
public final class AccountDeletionModel {
    /// 上一次刪除失敗時後端的訊息。
    public private(set) var errorMessage: String?
    public private(set) var isDeleting = false

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 確認訊息:資料全數刪除、無法復原。上游 ADR 0035(#121)起,家庭裡還有其他成員時管理權自動交給下一位成員,
    /// 不再連整個家庭一起刪除;只有最後一位成員刪帳才會連家庭一起刪除(#324)。
    public var confirmation: String {
        "刪除帳號會永久刪除你的帳戶、收支明細、儲蓄目標等所有個人資料，無法復原。如果家庭裡還有其他成員，管理權會自動交給下一位成員；如果你是最後一位成員，家庭也會一併刪除。"
    }

    public func clearError() {
        errorMessage = nil
    }

    public func delete() async {
        guard !isDeleting else { return }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "刪除帳號失敗" : message
            return
        }
        session.signOutAfterAccountDeletion()
    }
}
