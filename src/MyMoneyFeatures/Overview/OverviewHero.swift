import Charts
import MyMoneyDomain
import SwiftUI

/// 總覽最上面的主視覺(#116):超大的淨可用餘額，下面是後端預測的 30 天走勢線。
/// 這是 DESIGN.md「字級維持現狀」唯一的例外:全 app 最重要的一個數字，用「大數字」放大。
struct OverviewHero: View {
    let balance: Money
    let trend: ForecastTrend?
    /// 走勢線的 VoiceOver 摘要(最低餘額、日期、會不會透支)。
    let trendSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BigNumber(title: "淨可用餘額", amount: balance)
            if let trend, !trend.points.isEmpty {
                ForecastTrendChart(trend: trend, summary: trendSummary)
            }
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
    }
}

/// 30 天走勢線:零線是虛線，零以上用一般色、零以下紅色;不畫座標軸，只標「今天」和「30 天後」。
/// 只用後端的預測值(CLAUDE.md「不在 client 端重算業務規則」)。
struct ForecastTrendChart: View {
    let trend: ForecastTrend
    let summary: String?

    var body: some View {
        VStack(spacing: 4) {
            Chart {
                ForEach(trend.points, id: \.index) { point in
                    LineMark(x: .value("第幾天", point.index), y: .value("預測餘額", point.balance))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(lineStyle)
                }
                // 零線:線有碰到零以下才畫，否則整條都在零以上，不需要參考線。
                if trend.minimum < 0 {
                    RuleMark(y: .value("零", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .frame(height: 120)
            .accessibilityLabel(summary ?? "未來 30 天預測餘額")

            HStack {
                Text("今天")
                Spacer()
                Text("30 天後")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// 線的顏色:有跨過零線時，零線以上一般色、以下紅色(漸層在零線的位置硬切);全在零以下整條紅色。
    /// 一般色用主要文字色而不是主題色:這個 app 的主題色是品牌紅，跟警示紅分不出來。
    private var lineStyle: AnyShapeStyle {
        if trend.isEntirelyBelowZero { return AnyShapeStyle(.red) }
        guard let zero = trend.zeroFraction else { return AnyShapeStyle(Color.primary) }
        return AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: .primary, location: 0), .init(color: .primary, location: zero),
                    .init(color: .red, location: zero), .init(color: .red, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// 剛好是資料的最低到最高，漸層的切換點(`zeroFraction`)才會剛好落在零線上;
    /// 全部相同的值時撐出一點高度，線才不會貼在邊上。
    private var yDomain: ClosedRange<Double> {
        trend.minimum < trend.maximum ? trend.minimum...trend.maximum : (trend.minimum - 1)...(trend.maximum + 1)
    }
}

/// 主視覺的骨架屏:跟載入後一樣的大數字與一塊跟圖表一樣高的灰色區塊。
struct OverviewHeroSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BigNumber(title: "淨可用餘額", amount: Skeleton.amount)
            SkeletonChart(height: 120)
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .skeletonAnnouncement()
    }
}
