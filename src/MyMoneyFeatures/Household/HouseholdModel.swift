import Foundation
import MyMoneyDomain
import Observation

/// 帳號 sheet → 家庭(parity.md「家庭」)。
@MainActor
@Observable
public final class HouseholdModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var household: Household?
    /// 最近一次產生的邀請碼(sheet 顯示)。
    public var invitation: HouseholdInvitation?

    public var createName = ""
    public var joinCode = ""
    /// 操作失敗時顯示的訊息(alert)。
    public var alertMessage: String?
    public private(set) var isWorking = false

    @ObservationIgnored private let repository: any HouseholdRepository
    @ObservationIgnored private let dataVersion: DataVersion

    public init(repository: any HouseholdRepository, dataVersion: DataVersion) {
        self.repository = repository
        self.dataVersion = dataVersion
    }

    /// 名稱必填;還沒填好時停用按鈕(parity 刻意偏離第 23 項)。
    public var canCreate: Bool { !trimmedName.isEmpty && !isWorking }
    public var canJoin: Bool { !trimmedCode.isEmpty && !isWorking }

    public var memberCountText: String { "\(household?.members.count ?? 0) 位成員" }

    public let leaveConfirmation = "確定要退出這個家庭嗎？退出後將無法查看這個家庭的家庭公帳。"

    public func removeConfirmation(for member: HouseholdMember) -> String {
        "確定要將「\(member.name)」移出家庭嗎？"
    }

    /// 只有管理員看得到「移除」,而且只出現在一般成員上。
    public func canRemove(_ member: HouseholdMember) -> Bool {
        household?.myRole == .admin && member.role == .member
    }

    public func load() async {
        do {
            household = try await repository.current()
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func create() async {
        guard canCreate else { return }
        await perform { [repository, trimmedName] in try await repository.create(name: trimmedName) }
    }

    public func join() async {
        guard canJoin else { return }
        await perform { [repository, trimmedCode] in try await repository.join(code: trimmedCode) }
    }

    /// 每按一次產生一組新的邀請碼。
    public func invite() async {
        do {
            invitation = try await repository.invite()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    public func leave() async {
        await perform { [repository] in try await repository.leave() }
    }

    public func remove(_ member: HouseholdMember) async {
        await perform { [repository] in try await repository.removeMember(member.userID) }
    }

    private var trimmedName: String { createName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCode: String { joinCode.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 建立、加入、離開、移除成功後，資料版本遞增:淨可用資產、家庭公帳等資料的範圍都會跟著改變。
    private func perform(_ action: @escaping @Sendable () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        createName = ""
        joinCode = ""
        dataVersion.bump()
        await load()
    }
}

extension HouseholdRole {
    public var title: String {
        switch self {
        case .admin: "管理員"
        case .member: "一般成員"
        }
    }
}

extension HouseholdMember {
    /// 名稱的開頭字，英文轉大寫;沒有名稱時是「?」。
    public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    /// 加入日期，換成當地的日期，例如「2026/09/28」(parity 刻意偏離第 29 項)。
    public func joinedDateText(in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: joinedAt)
        return String(format: "%d/%02d/%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}
