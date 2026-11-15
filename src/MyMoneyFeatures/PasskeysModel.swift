import Foundation
import MyMoneyDomain
import Observation

/// 「帳號安全」的通行金鑰(passkey)區塊(#339,與 web 的設定頁對等):建立、改名、刪除。
@MainActor
@Observable
public final class PasskeysModel {
    /// 新的在前;載入之前是 `nil`(骨架屏)。
    public private(set) var passkeys: [Passkey]?
    /// 清單載入失敗的原因;畫面在那一區顯示它和「重試」。
    public private(set) var errorMessage: String?
    /// 建立、改名、刪除失敗時後端的訊息(alert)。使用者取消系統的 passkey 視窗不算失敗。
    public var alertMessage: String?
    /// 系統的 passkey 視窗開著,或正在送給後端驗證。
    public private(set) var isCreating = false

    @ObservationIgnored private let repository: any PasskeyRepository

    public init(repository: any PasskeyRepository) {
        self.repository = repository
    }

    public var isLoading: Bool { passkeys == nil && errorMessage == nil }

    public func deleteConfirmation(for passkey: Passkey) -> String {
        "確定要刪除「\(passkey.name)」嗎？之後就不能再用它登入，已登入的裝置不受影響。"
    }

    public func load() async {
        do {
            passkeys = try await repository.passkeys()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 名稱前後的空白去掉;空的由後端命名為「Passkey」。
    public func create(name: String) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        await perform { try await $0.create(name: name.trimmingCharacters(in: .whitespaces)) }
    }

    public func rename(_ passkey: Passkey, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        await perform { try await $0.rename(passkey.id, to: trimmed) }
    }

    public func delete(_ passkey: Passkey) async {
        await perform { try await $0.delete(passkey.id) }
    }

    /// 成功後重新載入清單;取消不顯示錯誤。
    private func perform(_ operation: (any PasskeyRepository) async throws -> Void) async {
        do {
            try await operation(repository)
        } catch is CancellationError {
            return
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        await load()
    }
}
