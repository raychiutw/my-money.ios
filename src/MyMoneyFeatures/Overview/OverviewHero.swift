import Charts
import MyMoneyDomain
import SwiftUI

/// 總覽最上面的主視覺(#116、#124):超大的淨可用餘額，下面是後端預測的 30 天走勢線;
/// 直接放在背景上，沒有卡片底(設計稿)。
/// 這是 DESIGN.md「字級維持現狀」唯一的例外:全 app 最重要的一個數字，用「大數字」放大。
struct OverviewHero: View {
    let balance: Money
    /// 淨可用餘額的組成(#178)三段，例如「現金 $1,500」「＋ 活存帳戶 $50,000」「− 信用卡待繳 $28,500」;VoiceOver 念 `compositionSpoken`。
    var compositionParts: [String]?
    var compositionSpoken: String?
    let trend: ForecastTrend?
    /// 走勢線的 VoiceOver 摘要(最低餘額、日期、會不會透支)。
    let trendSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BigNumber(title: "淨可用餘額", amount: balance)
            if let compositionParts {
                // 一行放得下就一行;放不下一段一行(現金、＋活存帳戶、−信用卡待繳)，不在「活存／帳戶」中間折斷。
                ViewThatFits(in: .horizontal) {
                    Text(compositionParts.joined(separator: " "))
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(compositionParts, id: \.self) { Text($0) }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(compositionSpoken ?? compositionParts.joined(separator: " "))
                .accessibilityIdentifier("overview.composition")
            }
            if let trend, !trend.points.isEmpty {
                ForecastTrendChart(trend: trend, summary: trendSummary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

/// 30 天走勢線:零線是虛線，零以上用一般色、零以下紅色，零以上的線下面有淡出的填色，起點(今天)有圓點;
/// 不畫座標軸，只標「今天」和「30 天後」。只用後端的預測值(CLAUDE.md「不在 client 端重算業務規則」)。
struct ForecastTrendChart: View {
    let trend: ForecastTrend
    let summary: String?

    var body: some View {
        VStack(spacing: 4) {
            Chart {
                // 填色:從零線(整條線都在零以上時從最低點)往上到線，由上往下淡出;零以下沒有填色。
                ForEach(trend.points, id: \.index) { point in
                    AreaMark(
                        x: .value("第幾天", point.index), yStart: .value("基準", fillBaseline),
                        yEnd: .value("預測餘額", max(point.balance, fillBaseline))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.24), Color.primary.opacity(0)], startPoint: .top, endPoint: .bottom
                        )
                    )
                    .accessibilityHidden(true)
                }
                ForEach(trend.points, id: \.index) { point in
                    LineMark(x: .value("第幾天", point.index), y: .value("預測餘額", point.balance))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(lineStyle)
                }
                // 今天:起點的圓點。
                if let first = trend.points.first {
                    PointMark(x: .value("第幾天", first.index), y: .value("預測餘額", first.balance))
                        .symbolSize(70)
                        .foregroundStyle(first.balance < 0 ? Color.red : Color.primary)
                        .accessibilityHidden(true)
                }
                // 零線:線有碰到零以下才畫，否則整條都在零以上，不需要參考線。
                if trend.minimum < 0 {
                    RuleMark(y: .value("零", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        // 明確的灰色:`.secondary` 在圖表裡會被預設的 tint 染色。
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .chartXScale(range: .plotDimension(padding: 8))
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
    /// 一般色用主要文字色:警示紅用在透支與負數，走勢線不用彩色。
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

    /// 填色的底:有碰到零以下時是零線，否則是最低點。
    private var fillBaseline: Double { max(0, trend.minimum) }

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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .skeletonAnnouncement()
    }
}
