import Foundation
import MyMoneyDomain

/// 儲蓄目標的合計與整體達成率:儲蓄目標頁與總覽的「儲蓄目標」入口共用同一個算法。
struct SavingsGoalTotals {
    let saved: Money
    let target: Money
    let monthlyReserve: Money

    init(_ goals: [SavingsGoal]) {
        saved = goals.reduce(.zero) { $0 + $1.savedAmount }
        target = goals.reduce(.zero) { $0 + $1.targetAmount }
        monthlyReserve = goals.reduce(.zero) { $0 + $1.monthlyReserve }
    }

    /// 整體達成率,取 1 位小數;目標金額合計是 0 時顯示「0%」(跟 web 一樣)。
    var overallRateText: String {
        guard target > .zero else { return "0%" }
        let rate = saved.amount / target.amount * 100
        return rate.percentText(fractionDigits: 1)
    }
}
