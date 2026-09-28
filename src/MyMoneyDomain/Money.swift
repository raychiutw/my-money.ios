import Foundation

/// 金額(新台幣)。後端存成 SQLite 的 REAL,這裡一律用 `Decimal`,不用 `Double`
/// (Apple 文件:「don't use Float or Double to represent currency」)。
public struct Money: Hashable, Comparable, Sendable {
    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    public static let zero = Money(0)

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount + rhs.amount)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(lhs.amount - rhs.amount)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }
}
