import Charts
import MyMoneyDomain
import SwiftUI

/// 家庭頁最上面的主視覺(#121):超大的分攤建議金額並標明誰轉給誰，下面是各成員本月公帳代墊的長條圖與平均線。
/// 數字都是後端的值(本月各成員的公帳代墊);分攤建議跟統計頁同一個算法。
struct HouseholdHero: View {
    let model: HouseholdModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let settlement = model.settlement {
                settlementView(settlement)
            } else if !model.shares.isEmpty {
                // 不是剛好兩位成員有公帳代墊:沒有分攤建議，大數字是本月公帳代墊的合計。
                let total = model.shares.reduce(Money.zero) { $0 + $1.total }
                BigNumber(title: "本月公帳代墊", amount: total, warnsWhenNegative: false)
            }
            if !model.shares.isEmpty {
                MemberShareChart(shares: model.shares, average: model.averageShare)
            }
        }
        .padding(.vertical, 8)
    }

    /// 轉帳金額是大數字，下面是誰轉給誰;兩人一樣多時大數字是每人負擔，下面是「不用轉帳」。
    /// VoiceOver 念完整的一句(跟統計頁一樣)。
    private func settlementView(_ settlement: Settlement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let transfer = settlement.transfer {
                BigNumber(title: "分攤建議", amount: transfer.amount, warnsWhenNegative: false)
                Text("\(transfer.from) 轉給 \(transfer.to)")
                    .font(.headline)
            } else {
                BigNumber(title: "分攤建議", amount: settlement.perPerson, warnsWhenNegative: false)
                Text("兩人一樣多，不用轉帳")
                    .font(.headline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("分攤建議,\(settlement.text(spoken: true))")
    }
}

/// 各成員本月公帳代墊的長條圖:每位成員一根，一條虛線是平均;數字標在每根上面，不只靠長度。
struct MemberShareChart: View {
    let shares: [HouseholdShare]
    let average: Money?

    var body: some View {
        Chart {
            ForEach(shares, id: \.userID) { share in
                BarMark(x: .value("成員", share.userName), y: .value("公帳代墊", share.total.chartValue))
                    .foregroundStyle(.indigo)
                    .annotation(position: .top) {
                        Text(share.total.formatted())
                            .font(.footnote.bold())
                            .monospacedDigit()
                    }
                    .accessibilityLabel(share.userName)
                    .accessibilityValue("公帳代墊 \(share.total.spokenText)")
            }
            if let average {
                RuleMark(y: .value("平均", average.chartValue))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("平均 \(average.formatted())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(max(shares.map(\.total.chartValue).max() ?? 1, average?.chartValue ?? 0) * 1.35))
        .frame(height: 160)
        .accessibilityLabel(summary)
    }

    /// 例如「本月各成員公帳代墊，平均 5,000 元」。
    private var summary: String {
        average.map { "本月各成員公帳代墊，平均 \($0.spokenText)" } ?? "本月各成員公帳代墊"
    }
}

/// 我的累計代墊、已報銷、待報銷(後端的值)三格數字磚;待報銷有餘額時紅色，已結清時綠色。
struct MyAdvanceTiles: View {
    let advance: HouseholdAdvance

    var body: some View {
        NumberTileRow {
            NumberTile(title: "累計代墊", amount: advance.totalAdvanced, spokenTitle: "我的累計公帳墊付")
            NumberTile(title: "已報銷", amount: advance.totalReimbursed, spokenTitle: "我的已獲撥款報銷")
            NumberTile(
                title: "待報銷", amount: advance.pendingReimbursement, style: advance.isSettled ? .green : .red,
                spokenTitle: "我的待報銷"
            )
        }
    }
}
