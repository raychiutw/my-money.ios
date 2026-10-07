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
                BigNumber(
                    title: "本月公帳代墊", amount: total, text: total.formatted(flow: .outflow), warnsWhenNegative: false,
                    style: total.tone(of: .outflow).color
                )
            }
            if !model.shares.isEmpty {
                MemberShareChart(shares: model.shares, average: model.averageShare)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

/// 各成員本月公帳代墊的長條圖:每位成員一根，金額標在長條裡面(白字，不會壓到平均線)，一條虛線是平均，
/// 平均的金額寫在圖下面的圖例;只標成員名字，不畫格線。
struct MemberShareChart: View {
    let shares: [HouseholdShare]
    let average: Money?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(shares, id: \.userID) { share in
                    BarMark(x: .value("成員", share.userName), y: .value("公帳代墊", share.total.chartValue))
                        .foregroundStyle(.indigo)
                        // 金額標在長條上方、照系統字級不縮小(#156);字比長條寬也不會被切,加底色才不會被平均線壓住。
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ShareAmountLabel(text: share.total.formatted())
                        }
                        .accessibilityLabel(share.userName)
                        .accessibilityValue("公帳代墊 \(share.total.spokenText)")
                }
                if let average {
                    RuleMark(y: .value("平均", average.chartValue))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        // 明確的灰色:`.secondary` 在圖表裡會被預設的 tint 染色。
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
            .annotationHeadroom()
            .accessibilityLabel(summary)

            if let average {
                HStack(spacing: 6) {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 20, y: 0))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 20, height: 1)
                    Text("平均 \(average.formatted())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityHidden(true)
            }
        }
    }

    /// 例如「本月各成員公帳代墊，平均 5,000 元」。
    private var summary: String {
        average.map { "本月各成員公帳代墊，平均 \($0.spokenText)" } ?? "本月各成員公帳代墊"
    }
}

/// 我的累計代墊、已報銷、待報銷(後端的值)三格數字磚;待報銷有餘額時是紅色負數，已結清不帶號、一般色(#202)。
struct MyAdvanceTiles: View {
    let advance: HouseholdAdvance

    var body: some View {
        NumberTileRow {
            NumberTile(title: "累計代墊", amount: advance.totalAdvanced, spokenTitle: "我的累計公帳墊付")
            NumberTile(title: "已報銷", amount: advance.totalReimbursed, spokenTitle: "我的已獲撥款報銷")
            NumberTile(
                title: "待報銷", amount: advance.pendingReimbursement, text: advance.pendingReimbursement.formatted(flow: .outflow),
                style: advance.pendingReimbursement.tone(of: .outflow).color,
                spokenTitle: "我的待報銷"
            )
        }
    }
}

/// 長條上方的金額:照系統字級、不縮小;加底色才不會被平均線壓住。
private struct ShareAmountLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.bold())
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 4)
            .background(.background, in: Capsule())
    }
}
