import Foundation
import MyMoneyDomain

/// `GET /accounts/:id/rollover-preview`(上游 ADR 0024)。頂層是 camelCase，裡面的明細是 snake_case，旗標有 0/1 也有 true/false。
/// 還有 `card`、`totalExpense`、`netRolledAmount`、`projectedBalance` 等後端算好的合計，不解碼:試算一律由 `StatementPreview.outlook` 做，
/// 開窗時跟後端的數字一致(`AccountsTranslationTests.outlookMatchesTheBackend`)。
struct StatementPreviewDTO: Decodable {
    struct ItemDTO: Decodable {
        let id: String
        let amount: Decimal
        let isShared: Int
        let type: String
        let category: String
        let note: String?
        let date: String
        let deferToNextStatement: Int
        let isBilled: Int?
        let isPriorDeferred: Bool?
        let isInitiallyDeferred: Bool?

        enum CodingKeys: String, CodingKey {
            case id, amount, type, category, note, date
            case isShared = "is_shared"
            case deferToNextStatement = "defer_to_next_statement"
            case isBilled = "is_billed"
            case isPriorDeferred = "is_prior_deferred"
            case isInitiallyDeferred = "is_initially_deferred"
        }
    }

    /// 沒設結帳日的卡是空字串。
    let statementDate: String?
    let prevStatementDate: String?
    let baseNetBilled: Decimal
    let totalRepay: Decimal?
    let baseNetUnbilled: Decimal
    let hasRolledCycle: Bool?
    let priorDeferredCount: Int?
    let transactions: [ItemDTO]?

    func preview() throws -> StatementPreview {
        let statement = statementDate.flatMap(CalendarDay.init(iso:))
        let previous = prevStatementDate.flatMap(CalendarDay.init(iso:))
        let rolled = hasRolledCycle ?? false
        let items: [StatementItem] = try (transactions ?? []).compactMap { dto in
            guard let date = CalendarDay(iso: dto.date) else { throw RepositoryError.unreadableResponse }
            // 後端只回信用卡的消費(expense)與刷退(income);看不懂的類型略過那一筆。
            let kind: StatementItem.Kind
            switch dto.type {
            case "expense": kind = .expense
            case "income": kind = .refund
            default: return nil
            }
            // 旗標是後端 `10b7b03` 才加的;舊的回應沒有時照 web 的備援算法自己推:交易日在上一個結帳日(含)之前、還沒出帳的是上期延入，
            // 首次結算(還沒出過帳)預設納入本期，其餘看是不是標了延至下期。
            let priorDeferred = dto.isPriorDeferred ?? (previous.map { date <= $0 } == true && (dto.isBilled ?? 0) == 0)
            let initiallyDeferred = dto.isInitiallyDeferred ?? ((priorDeferred && !rolled) ? false : dto.deferToNextStatement == 1)
            return StatementItem(
                id: TransactionID(dto.id), kind: kind, amount: Money(dto.amount), date: date,
                category: TransactionCategory(dto.category), note: dto.note ?? "", isShared: dto.isShared == 1,
                isPriorDeferred: priorDeferred, isInitiallyDeferred: initiallyDeferred
            )
        }
        return StatementPreview(
            statementDate: statement, previousStatementDate: previous, items: items,
            baseNetBilled: Money(baseNetBilled), totalRepay: Money(totalRepay ?? 0), baseNetUnbilled: Money(baseNetUnbilled),
            hasRolledCycle: rolled, priorDeferredCount: priorDeferredCount ?? 0
        )
    }
}

/// `POST /accounts/:id/rollover-statement` 的 body:要延至下期的明細。排序固定，不依集合的順序。
struct RolloverBody: Encodable {
    let deferredTxIds: [String]

    init(deferring: Set<TransactionID>) {
        deferredTxIds = deferring.map(\.rawValue).sorted()
    }
}
