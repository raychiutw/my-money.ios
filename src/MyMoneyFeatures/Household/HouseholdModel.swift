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
    /// 各成員本月的公帳代墊(`GET /statistics/household-shares`，#121):長條圖與分攤建議的資料。
    /// 取不到(沒有統計資料來源或取得失敗)時是空的，家庭頁其餘區塊照常顯示。
    public private(set) var shares: [HouseholdShare] = []
    /// 就地展開明細的成員;可以同時展開多位。
    private var expandedMemberIDs: Set<UserID> = []

    @ObservationIgnored private let repository: any HouseholdRepository
    @ObservationIgnored private let accounts: any AccountRepository
    @ObservationIgnored private let statistics: (any StatisticsRepository)?
    @ObservationIgnored private let currentUser: UserID?
    /// 載入家庭之後同步角色，帳戶頁、交易頁的編輯權限跟著改(上游 ADR 0013、#133)。
    @ObservationIgnored private let permissions: PermissionsModel?
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let defaults: UserDefaults

    /// 骨架屏的形狀(#204):上次載入時有沒有家庭、幾位成員;沒有記錄時畫成還沒加入(沒有家庭的人比較多)。
    public enum SkeletonShape: Equatable, Sendable {
        case notJoined
        /// `hasMyAdvance`:上次有我自己的代墊統計(三格數字磚);沒有時整個區塊不畫。
        case joined(members: Int, hasMyAdvance: Bool)
    }

    public var skeletonShape: SkeletonShape {
        let memory = SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.household")
        guard memory.flag(for: "joined") == true else { return .notJoined }
        return .joined(members: memory.count(for: "members", default: 2), hasMyAdvance: memory.flag(for: "myAdvance") ?? true)
    }

    /// 數字磚排法的記憶(#204),同總覽。
    public var tileLayoutMemory: TileLayoutMemory { TileLayoutMemory(defaults: defaults, key: "household.tileLayout") }

    /// `locale` 決定日期的格式，預設跟著系統。
    public init(
        repository: any HouseholdRepository,
        accounts: any AccountRepository,
        statistics: (any StatisticsRepository)? = nil,
        currentUser: UserID? = nil,
        permissions: PermissionsModel? = nil,
        dataVersion: DataVersion,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.defaults = defaults
        self.repository = repository
        self.accounts = accounts
        self.statistics = statistics
        self.currentUser = currentUser
        self.permissions = permissions
        self.dataVersion = dataVersion
        self.locale = locale
        self.today = today
    }

    /// 代墊與報銷明細的日期，例如「9月27日」,不是今年的加上年份。
    public func dateText(_ day: CalendarDay) -> String {
        day.text(today: today(), locale: locale)
    }

    /// 代墊與報銷明細的「日期 時間」(上游 718ace9、#207),例如「9月27日 03:57」(台灣時間);沒有時間只有日期。
    public func dateTimeText(_ day: CalendarDay, _ time: Date?) -> String {
        [dateText(day), time.map(RecordedTime.clockText(of:))].compactMap { $0 }.joined(separator: " ")
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

    /// 有待報銷才能從共同基金撥款報銷(web 的 `b1382f4`:收款帳戶改用代墊統計附的可收款帳戶);
    /// 上游 ADR 0013(#48):家庭管理員可以替任何成員撥款，一般成員只能對自己的代墊款撥款，後端對其他人回 403，
    /// 所以他人的卡片不顯示入口。不知道登入的是誰時，一般成員一律沒有入口。
    public func canReimburse(_ advance: HouseholdAdvance) -> Bool {
        !advance.isSettled && (household?.myRole == .admin || advance.memberID == currentUser)
    }

    /// 只有家庭管理員可以產生邀請碼(上游 ADR 0013,#47);一般成員呼叫會得到 403。
    public var canInvite: Bool { household?.myRole == .admin }

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

    /// 只有家庭管理員看得到「移除」,而且只出現在一般成員上。
    public func canRemove(_ member: HouseholdMember) -> Bool {
        household?.myRole == .admin && member.role == .member
    }

    public func load() async {
        do {
            household = try await repository.current()
            permissions?.update(role: household?.myRole)
            advances = household == nil ? [] : try await repository.advances()
            // 本月各成員的公帳代墊是額外的資料來源:取不到不能讓家庭頁失敗。
            shares = household == nil ? [] : await fetchShares()
            let memory = SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.household")
            memory.record(flag: household != nil, for: "joined")
            memory.record(count: household?.members.count ?? 0, for: "members")
            memory.record(flag: myAdvance != nil, for: "myAdvance")
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func fetchShares() async -> [HouseholdShare] {
        guard let statistics else { return [] }
        return (try? await statistics.householdShares(month: CalendarMonth(today()))) ?? []
    }

    /// 分攤建議(#121):剛好兩位成員有公帳代墊款時，平分後誰轉多少給誰;跟統計頁同一個算法(parity「前端常數」)。
    public var settlement: Settlement? { StatisticsModel.settlement(for: shares) }

    /// 長條圖的平均線:各成員本月公帳代墊的平均(四捨五入到整數)，只是顯示;沒有資料時是 `nil`。
    public var averageShare: Money? {
        guard !shares.isEmpty else { return nil }
        let total = shares.reduce(Money.zero) { $0 + $1.total }.amount
        var average = total / Decimal(shares.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &average, 0, .plain)
        return Money(rounded)
    }

    /// 登入的人在代墊統計裡的那一筆:我的累計代墊、已報銷、待報銷(後端的值)。
    public var myAdvance: HouseholdAdvance? {
        guard let currentUser else { return nil }
        return advances.first { $0.memberID == currentUser }
    }

    /// 成員的身分，例如「家庭管理員」「一般成員」;不是這個家庭的成員時是 `nil`。
    public func roleTitle(of userID: UserID) -> String? {
        household?.members.first { $0.userID == userID }?.role.title
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
        case .admin: "家庭管理員"
        case .member: "一般成員"
        }
    }
}

extension HouseholdMember {
    /// 名稱的開頭字，英文轉大寫;沒有名稱時是「?」。
    public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}
