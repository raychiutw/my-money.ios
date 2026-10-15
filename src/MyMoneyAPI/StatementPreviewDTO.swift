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
        let isPriorDeferred: Bool
        let isInitiallyDeferred: Bool

        enum CodingKeys: String, CodingKey {
            case id, amount, type, category, note, date
            case isShared = "is_shared"
            case isPriorDeferred = "is_prior_deferred"
            case isInitiallyDeferred = "is_initially_deferred"
        }
    }

    /// 沒設結帳日的卡是空字串。
    let statementDate: String
    let prevStatementDate: String
    let baseNetBilled: Decimal
    let totalRepay: Decimal
    let baseNetUnbilled: Decimal
    let hasRolledCycle: Bool
    let priorDeferredCount: Int
    let transactions: [ItemDTO]

    /// 旗標與基準值都必填:prod 已部署(`10b7b03`),少了就是看不懂的回應。不照 web 在舊後端上自己推旗標的備援
    /// (那是 client 端重算業務規則，parity 第 78 項)。看不懂的明細類型也整份失敗，不默默少一筆:基準值是後端把它算進去的。
    func preview() throws -> StatementPreview {
        let items: [StatementItem] = try transactions.map { dto in
            guard let date = CalendarDay(iso: dto.date) else { throw RepositoryError.unreadableResponse }
            let kind: StatementItem.Kind
            switch dto.type {
            case "expense": kind = .expense
            case "income": kind = .refund
            default: throw RepositoryError.unreadableResponse
            }
            return StatementItem(
                id: TransactionID(dto.id), kind: kind, amount: Money(dto.amount), date: date,
                category: TransactionCategory(dto.category), note: dto.note ?? "", isShared: dto.isShared == 1,
                isPriorDeferred: dto.isPriorDeferred, isInitiallyDeferred: dto.isInitiallyDeferred
            )
        }
        return StatementPreview(
            statementDate: CalendarDay(iso: statementDate), previousStatementDate: CalendarDay(iso: prevStatementDate), items: items,
            baseNetBilled: Money(baseNetBilled), totalRepay: Money(totalRepay), baseNetUnbilled: Money(baseNetUnbilled),
            hasRolledCycle: hasRolledCycle, priorDeferredCount: priorDeferredCount
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
