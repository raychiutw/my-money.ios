import MyMoneyDomain
import SwiftUI

/// 首次載入的骨架屏(DESIGN.md「載入狀態」,web `865b508` 的骨架屏)。
///
/// 各畫面的「載入中」用跟載入後一樣的元件排版，內容用這裡的固定佔位資料，每一列套 `skeletonRow()`;
/// 第一列改用 `skeletonAnnouncement()`,整個骨架屏 VoiceOver 只念一次「載入中」。
/// 不做微光(shimmer)動效：系統沒有內建，HIG 也不要求(parity 刻意偏離)。
enum Skeleton {
    /// 只用來撐出版面寬度;套上 `.redacted` 後不會顯示數字。
    static let amount = Money(88_888)
    /// 數字磚的佔位金額:跟真實內容一樣寬(含負號的六位數),欄數規則才會跟真實畫面算出同樣的結果(#201)。
    static let tileAmount = Money(-888_888)
    static let text = "佔位文字佔位文字"
    static let upcomingEvent = UpcomingEvent(
        event: ForecastEvent(
            date: CalendarDay(year: 2026, month: 1, day: 1), name: "預定收支名稱", type: .expense, amount: Money(888), key: "skeleton",
            canSettle: true
        ),
        dateText: "1月1日", subtitle: "個人私帳", amountText: "−$888", spokenText: ""
    )
    static let accountCard = OverviewAccountCard(
        BankAccount(id: AccountID("skeleton"), name: "帳戶名稱", colorHex: "#A8D8EA", balance: Skeleton.amount, isJointFund: false)
    )
    static let transaction = MyMoneyDomain.Transaction(
        id: TransactionID("skeleton"), accountID: AccountID("skeleton"), accountName: "佔位帳戶", type: .expense,
        category: .dining, amount: Money(888), note: "佔位備註", date: CalendarDay(year: 2026, month: 1, day: 1),
        isShared: true, recorderName: "佔位"
    )
}

extension View {
    /// 骨架屏的一列：系統的佔位樣式、不能點,VoiceOver 略過。
    func skeletonRow() -> some View {
        modifier(SkeletonRow())
    }

    /// 骨架裡的一格(#201):UI 測試要量骨架的欄數與格數,所以只有 `exposesSkeletonToAccessibility` 時才變成可查詢的元素。
    func skeletonCell(_ identifier: String) -> some View {
        modifier(SkeletonCell(identifier: identifier))
    }

    /// 骨架屏的第一列：跟 `skeletonRow()` 一樣，但 VoiceOver 念「載入中」。
    func skeletonAnnouncement() -> some View {
        redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("載入中")
    }

    /// 資料回來時淡入;開啟「減少動態效果」時不做動畫。
    func skeletonTransition<Value: Equatable>(value: Value) -> some View {
        modifier(SkeletonTransition(value: value))
    }
}

/// 骨架屏的區塊標題：跟載入後一樣顯示，但 VoiceOver 略過(只念「載入中」)。
struct SkeletonHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .accessibilityHidden(true)
    }
}

/// 骨架屏的一個區塊：`count` 列同樣的佔位列;`announces` 時第一列負責念「載入中」。
struct SkeletonSection<Row: View>: View {
    var title: String?
    var count: Int
    var announces = false
    @ViewBuilder var row: () -> Row

    var body: some View {
        Section {
            ForEach(0..<count, id: \.self) { index in
                if announces && index == 0 {
                    row().skeletonAnnouncement()
                } else {
                    row().skeletonRow()
                }
            }
        } header: {
            if let title {
                SkeletonHeader(title)
            }
        }
    }
}

/// 統計卡的佔位(`SummaryRow` 的版面)。
struct SkeletonSummaryRow: View {
    var body: some View {
        SummaryRow(title: "統計卡標題", amount: Skeleton.amount, detail: Skeleton.text)
    }
}

/// 兩行項目的佔位：名稱、說明、金額(週期收支、預定收支、已綁定的帳號)。
struct SkeletonItemRow: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("項目名稱")
                Text(Skeleton.text)
                    .font(.subheadline)
            }
            Spacer()
            Text(Skeleton.amount.formatted())
                .monospacedDigit()
        }
    }
}

/// 圖表的佔位：跟圖表一樣高的灰色區塊。
struct SkeletonChart: View {
    var height: CGFloat = 200

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(height: height)
    }
}

extension EnvironmentValues {
    /// UI 測試用(`-uiTesting` 才開):骨架屏不對 VoiceOver 隱藏,測試才查得到骨架每一格的位置。一般使用者永遠是 `false`。
    @Entry public var exposesSkeletonToAccessibility = false
}

private struct SkeletonRow: ViewModifier {
    @Environment(\.exposesSkeletonToAccessibility) private var exposed

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(!exposed)
    }
}

private struct SkeletonCell: ViewModifier {
    let identifier: String
    @Environment(\.exposesSkeletonToAccessibility) private var exposed

    func body(content: Content) -> some View {
        if exposed {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("骨架")
                .accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct SkeletonTransition<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: value)
    }
}
