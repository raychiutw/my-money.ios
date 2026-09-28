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
    /// 操作成功時顯示的訊息(例如撥款報銷的結果)。
    public var noticeMessage: String?
    public private(set) var isWorking = false
    /// 邀請碼還在產生中;這段期間再按「邀請」不會多產生一組。
    public private(set) var isInviting = false

    /// 每位成員的家庭公帳代墊統計(web 的「家庭公帳代墊與報銷中心」)。
    public private(set) var advances: [HouseholdAdvance] = []
    /// 就地展開明細的成員;可以同時展開多位。
    private var expandedMemberIDs: Set<UserID> = []

    @ObservationIgnored private let repository: any HouseholdRepository
    @ObservationIgnored private let accounts: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let currentUserID: UserID?
    @ObservationIgnored private let today: () -> CalendarDay

    /// `currentUserID`:登入的人，用來判斷能不能撥款報銷(只能報銷自己的代墊款)。
    public init(
        repository: any HouseholdRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        currentUserID: UserID?,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.accounts = accounts
        self.dataVersion = dataVersion
        self.currentUserID = currentUserID
        self.today = today
    }

    public func isShowingDetails(of memberID: UserID) -> Bool {
        expandedMemberIDs.contains(memberID)
    }

    public func toggleDetails(of memberID: UserID) {
        if expandedMemberIDs.contains(memberID) {
            expandedMemberIDs.remove(memberID)
        } else {
            expandedMemberIDs.insert(memberID)
        }
    }

    /// 只能從共同基金報銷自己的代墊款:後端的 `GET /accounts` 不回傳其他成員的個人帳戶，選不到收款帳戶
    /// (web 也送不出去，已回報 onion523/my-money#9)。
    public func canReimburse(_ advance: HouseholdAdvance) -> Bool {
        advance.memberID == currentUserID && !advance.isSettled
    }

    /// 其他成員還有待報銷時，說明為什麼不能從這裡報銷。
    public func reimbursementNote(for advance: HouseholdAdvance) -> String? {
        guard advance.memberID != currentUserID, !advance.isSettled else { return nil }
        return "後端目前不提供其他成員的收款帳戶，請由\(advance.memberName)本人撥款報銷。"
    }

    public func makeReimbursement(for advance: HouseholdAdvance) -> ReimbursementModel {
        ReimbursementModel(advance: advance, households: repository, accounts: accounts, dataVersion: dataVersion, today: today)
    }

    /// 名稱必填;還沒填好時停用按鈕(parity 刻意偏離第 23 項)。
    public var canCreate: Bool { !trimmedName.isEmpty && !isWorking }
    public var canJoin: Bool { !trimmedCode.isEmpty && !isWorking }

    public var memberCountText: String { "\(household?.members.count ?? 0) 位成員" }

    public let leaveConfirmation = "確定要退出這個家庭群組嗎？退出後將無法查看這個家庭群組的家庭公帳。"

    public func removeConfirmation(for member: HouseholdMember) -> String {
        "確定要將「\(member.name)」移出家庭群組嗎？"
    }

    /// 只有管理員看得到「移除」,而且只出現在一般成員上。
    public func canRemove(_ member: HouseholdMember) -> Bool {
        household?.myRole == .admin && member.role == .member
    }

    public func load() async {
        do {
            household = try await repository.current()
            advances = household == nil ? [] : try await repository.advances()
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
        guard !isInviting else { return }
        isInviting = true
        defer { isInviting = false }
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
