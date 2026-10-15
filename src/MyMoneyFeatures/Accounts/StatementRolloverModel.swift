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

    /// 本期結算區間:上一個結帳日的次日到這一期的結帳日;沒有結帳日的卡不分期，所有未出帳的消費都算。
    public var periodText: String? {
        guard let preview else { return nil }
        guard let end = preview.statementDate else { return "所有未出帳的消費" }
        guard let previous = preview.previousStatementDate else { return "至 \(dayText(end))" }
        return "\(dayText(previous.addingDays(1))) ～ \(dayText(end))"
    }

    /// 有上期延入款、而且這一期還沒出過帳才提示:這些款項首次結算預設納入本期(也可以再延一次)。
    public var priorDeferredNote: String? {
        guard let preview, preview.priorDeferredCount > 0, !preview.hasRolledCycle else { return nil }
        return "含 \(preview.priorDeferredCount) 筆上期延入款，已預設納入本期"
    }

    /// 明細第二行:日期;上期延入款後面加標記。
    public func itemDetailText(_ item: StatementItem) -> String {
        [dayText(item.date), item.isPriorDeferred ? "上期延入" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func dayText(_ day: CalendarDay) -> String { day.text(today: today(), locale: locale) }

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
