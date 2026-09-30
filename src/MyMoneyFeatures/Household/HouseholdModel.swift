import Foundation
import MyMoneyDomain
import Observation

/// 家庭 tab(parity.md「家庭」)。
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
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale

    /// `locale` 決定日期的格式，預設跟著系統。
    public init(
        repository: any HouseholdRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.accounts = accounts
        self.dataVersion = dataVersion
        self.locale = locale
        self.today = today
    }

    /// 加入日期(台灣時間的那一天),例如「9月28日」,不是今年的加上年份(DESIGN.md「日期」)。
    public func joinedDateText(of member: HouseholdMember) -> String {
        member.joinedAt.dayText(today: today(), locale: locale)
    }

    /// 代墊與報銷明細的日期，例如「9月27日」,不是今年的加上年份。
    public func dateText(_ day: CalendarDay) -> String {
        day.text(today: today(), locale: locale)
    }

    /// 邀請碼的有效期限(台灣時間),例如「10月5日 下午3:00」,不是今年的加上年份。
    public func expiryText(of invitation: HouseholdInvitation) -> String {
        invitation.expiresAt.dateTimeText(today: today(), locale: locale)
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

    /// 有待報銷就能從共同基金撥款報銷，不限本人(web 的 `b1382f4`:收款帳戶改用代墊統計附的可收款帳戶)。
    public func canReimburse(_ advance: HouseholdAdvance) -> Bool {
        !advance.isSettled
    }

    public func makeReimbursement(for advance: HouseholdAdvance) -> ReimbursementModel {
        ReimbursementModel(advance: advance, households: repository, accounts: accounts, dataVersion: dataVersion, today: today)
    }

    /// 名稱必填;還沒填好時停用按鈕(parity 刻意偏離第 23 項)。
    public var canCreate: Bool { !trimmedName.isEmpty && !isWorking }
    public var canJoin: Bool { !trimmedCode.isEmpty && !isWorking }

    public var memberCountText: String { "\(household?.members.count ?? 0) 位成員" }

    /// 離開與移除成員的確認訊息帶家庭名稱:「離開家庭」在中文裡像離開真正的家人，語氣比較重，
    /// 有名稱才看得出是 app 裡的家庭(ADR-0005)。家庭還沒載入時退回「這個家庭」。
    public var leaveConfirmation: String {
        "確定要退出\(familyNameForConfirmation)嗎？退出後將無法查看這個家庭的家庭公帳。"
    }

    public func removeConfirmation(for member: HouseholdMember) -> String {
        "確定要將「\(member.name)」移出\(familyNameForConfirmation)嗎？"
    }

    private var familyNameForConfirmation: String {
        household.map { "「\($0.name)」" } ?? "這個家庭"
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

    /// 建立、加入、離開、移除成功後，資料版本遞增:淨可用餘額、家庭公帳等資料的範圍都會跟著改變。
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
}
