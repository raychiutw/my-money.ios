import Foundation
import MyMoneyDomain
import Observation

/// 結帳日出帳作業的預覽 sheet(上游 ADR 0024,web 的「結帳日出帳作業預覽」Modal)。
///
/// 打開時載入這一期結帳區間的全部消費與刷退;使用者逐筆切換「延至下期」，摘要(出帳淨額、出帳後待繳款、剩餘未出帳款)就地重算，
/// 都不寫入後端——按「確認」才一次送出延期的明細，後端依明細重算餘額(冪等);取消就什麼都沒發生。
@MainActor
@Observable
public final class StatementRolloverModel: Submitting, Identifiable {
    public let card: CreditCard

    /// 沒設結帳日的卡不能出帳作業(上游 ADR 0030:後端回 400);入口先擋下並請使用者設定。
    public static let missingStatementDayMessage = "請先設定每月結帳日，才能做出帳作業"

    /// 還沒載入完(或載入失敗)時是 `nil`。
    public private(set) var preview: StatementPreview?
    /// 目前選的「延至下期」明細;載入完是開窗時已經延期的那些，之後由使用者切換。
    public private(set) var deferredIDs: Set<TransactionID> = []

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false
    public private(set) var isLoading = false

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale

    init(
        card: CreditCard,
        repository: any AccountRepository,
        dataVersion: DataVersion,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay
    ) {
        self.card = card
        self.repository = repository
        self.dataVersion = dataVersion
        self.locale = locale
        self.today = today
    }

    /// 載入預覽。**只載入一次**:從別的頁返回時 `.task` 會再跑，不能把使用者切換過的延期洗掉;載入失敗後才會再載入。
    public func load() async {
        guard preview == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let loaded = try await repository.statementPreview(card.id)
            preview = loaded
            deferredIDs = loaded.initiallyDeferredIDs
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    public var items: [StatementItem] { preview?.items ?? [] }

    /// 依目前選的延期試算的結果;還沒載入時是 `nil`。
    public var outlook: StatementOutlook? { preview?.outlook(deferring: deferredIDs) }

    public var deferredCount: Int { outlook?.deferredCount ?? 0 }

    /// 載入完了，但這一期沒有任何刷卡記錄:沒有東西可以出帳(後端會拒絕)。
    public var isEmptyCycle: Bool { preview != nil && items.isEmpty }

    public var canConfirm: Bool { preview != nil && !isEmptyCycle && !isSaving }

    public func isDeferred(_ id: TransactionID) -> Bool { deferredIDs.contains(id) }

    public func toggleDeferral(_ id: TransactionID) {
        if deferredIDs.contains(id) { deferredIDs.remove(id) } else { deferredIDs.insert(id) }
    }

    /// 結算區間:後端算好的起訖日(上游 ADR 0030),iOS 不自己推算。
    public var periodText: String? {
        guard let preview else { return nil }
        return "\(dayText(preview.startDate)) ～ \(dayText(preview.endDate))"
    }

    /// 區間的說明:本月結帳日還沒到時結算的是上一期帳單。
    public var periodNote: String? {
        guard let pending = preview?.isStatementPending else { return nil }
        return pending ? "結帳日還沒到，結算上一期帳單" : "結算本期帳單"
    }

    /// 有上期延入款、而且這一期還沒出過帳才提示:這些款項首次結算預設納入本期(也可以再延一次)。
    public var priorDeferredNote: String? {
        guard let preview, preview.priorDeferredCount > 0, !preview.hasRolledCycle else { return nil }
        return "含 \(preview.priorDeferredCount) 筆上期延入款，已預設納入本期"
    }

    /// 明細第二行:日期;上期延入款與公帳的家庭報銷狀態後面加標記。
    public func itemDetailText(_ item: StatementItem) -> String {
        [dayText(item.date), item.isPriorDeferred ? "上期延入" : nil, householdText(of: item)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// 明細卡的日期那一行(#283)。
    public func itemDayText(_ item: StatementItem) -> String { dayText(item.date) }

    /// 明細卡的狀態膠囊(#283):上期延入、公帳的家庭報銷狀態;都沒有就沒有膠囊。
    public func itemBadgeText(_ item: StatementItem) -> String? {
        let parts = [item.isPriorDeferred ? "上期延入" : nil, householdText(of: item)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    private func dayText(_ day: CalendarDay) -> String { day.text(today: today(), locale: locale) }

    /// 公帳明細的支付狀態文字。家庭共同帳戶的信用卡直接扣款(不是代墊),沒有「待報銷」之類的狀態,只寫「家庭公帳」。
    private func householdText(of item: StatementItem) -> String? {
        guard let payment = item.householdPayment else { return nil }
        return OwnershipName.title(isShared: true, payment: card.isJointFund ? .jointFund : payment)
    }

    /// 確認出帳;成功回傳後端的訊息(畫面關閉 sheet 並顯示)，並遞增資料版本讓其他畫面重抓。
    public func submit() async -> String? {
        errorMessage = nil
        guard let message = await submitting(failure: "出帳作業失敗", {
            try await repository.rollOverStatement(card.id, deferring: deferredIDs)
        }) else { return nil }
        dataVersion.bump()
        return message
    }
}
