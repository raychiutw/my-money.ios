import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 儲蓄目標：摘要(一個主數字加一般列),有截止日與沒有截止日兩組(parity.md「儲蓄目標」)。
struct SavingsGoalsScreen: View {
    @Bindable var model: SavingsGoalsModel
    @State private var sheet: ActiveSheet?
    @State private var pendingDeletion: SavingsGoal?

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("儲蓄目標")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sheet = .editor(model.makeEditor())
                    } label: {
                        Label("建立儲蓄目標", systemImage: "plus")
                    }
                    .accessibilityIdentifier("goals.add")
                }
            }
            .task(id: model.dataVersion.value) {
                await model.refreshIfStale()
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .editor(let editor): SavingsGoalEditorView(model: editor)
                case .deposit(let deposit): SavingsGoalDepositView(model: deposit)
                }
            }
            .alert(
                "刪除儲蓄目標",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { goal in
                Button("刪除", role: .destructive) {
                    Task { await model.delete(goal) }
                }
                Button("取消", role: .cancel) {}
            } message: { goal in
                Text(model.deleteConfirmation(for: goal))
            }
            .alert(
                "無法刪除",
                isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(model.alertMessage ?? "")
            }
    }

    /// 建立、編輯與存入共用一個 sheet。
    private enum ActiveSheet: Identifiable {
        case editor(SavingsGoalEditorModel)
        case deposit(SavingsGoalDepositModel)

        var id: ObjectIdentifier {
            switch self {
            case .editor(let model): ObjectIdentifier(model)
            case .deposit(let model): ObjectIdentifier(model)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                Section {
                    SummaryRow(title: "已存金額合計", amount: .plain(Skeleton.amount))
                        .skeletonAnnouncement()
                    ForEach(0..<3, id: \.self) { _ in
                        AmountRow(title: "摘要數字", amount: .plain(Skeleton.amount))
                            .skeletonRow()
                    }
                }
                // 跟著實際內容(#204 核對):有截止日、沒有截止日兩區各自的筆數(0 筆的區不畫),標題帶筆數。
                let counts = model.skeletonCounts
                if counts.dated > 0 {
                    SkeletonSection(title: "有截止日的目標(\(counts.dated))", count: counts.dated) { skeletonGoalRow }
                }
                if counts.undated > 0 {
                    SkeletonSection(title: "沒有截止日的目標(\(counts.undated))", count: counts.undated) { skeletonGoalRow }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入儲蓄目標", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                GlassCapsuleButton(title: "重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            List {
                // 摘要：已存金額合計是主數字，其餘是一般列(DESIGN.md「列與欄位」第 6 條，#77)。
                Section {
                    SummaryRow(title: "已存金額合計", amount: .plain(model.totalSaved))
                    AmountRow(title: "目標金額合計", amount: .plain(model.totalTarget))
                    LabeledContent("整體達成率") {
                        // 值用主要文字色，跟同一區 `AmountRow` 的金額一致(`LabeledContent` 預設是次要文字色)。
                        Text(model.overallRateText)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("整體達成率")
                    .accessibilityValue(model.overallRateText)
                    AmountRow(title: "每月預留合計", amount: .plain(model.totalMonthlyReserve))
                }
                if model.goals.isEmpty {
                    Section {
                        Text("尚未設立任何儲蓄目標")
                            .foregroundStyle(.secondary)
                    }
                }
                goalSection("有截止日的目標", goals: model.datedGoals)
                goalSection("沒有截止日的目標", goals: model.undatedGoals)
            }
            .refreshable { await model.load() }
        }
    }

    private var skeletonGoalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonItemRow()
            ProgressView(value: 0.4)
        }
    }

    @ViewBuilder
    private func goalSection(_ title: String, goals: [SavingsGoal]) -> some View {
        if !goals.isEmpty {
            Section("\(title)(\(goals.count))") {
                ForEach(goals) { goal in
                    SavingsGoalRow(goal: goal, deadline: model.deadlineText(of: goal)) {
                        sheet = model.makeDeposit(for: goal).map(ActiveSheet.deposit)
                    }
                    .swipeActions {
                        DestructiveSwipeButton { pendingDeletion = goal }
                        NeutralSwipeButton(title: "編輯", systemImage: "pencil") {
                            sheet = .editor(model.makeEditor(editing: goal))
                        }
                    }
                    .contextMenu {
                        if let deposit = model.makeDeposit(for: goal) {
                            Button("存入", systemImage: "plus.circle") {
                                sheet = .deposit(deposit)
                            }
                        }
                        Button("編輯", systemImage: "pencil") {
                            sheet = .editor(model.makeEditor(editing: goal))
                        }
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            pendingDeletion = goal
                        }
                    }
                }
            }
        }
    }
}

/// 一個儲蓄目標：圖示、名稱、截止日、已存金額、目標金額、進度、每月預留，以及「存入」(#77)。
/// 百分比交給進度條，畫面上不另外寫;VoiceOver 念百分比。已達成時用成功色，並停用存入(parity 刻意偏離第 6 項)。
/// 已存和目標放不下同一行時(大字級)改成上下堆疊，金額一律單行。
private struct SavingsGoalRow: View {
    let goal: SavingsGoal
    /// 截止日的文字(畫面 model 依系統格式產生);沒有截止日是 `nil`。
    let deadline: String?
    let deposit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 圖示和名稱並排放不下時(大字級)改成上下堆疊，截止日才不會被擠成好幾行。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    iconView
                    titles
                }
                VStack(alignment: .leading, spacing: 4) {
                    iconView
                    titles
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    saved
                    Spacer()
                    target
                }
                // 堆疊時金額靠右(#149)。
                VStack(alignment: .trailing, spacing: 2) {
                    saved
                    target
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            ProgressView(value: goal.progress)
                .tint(goal.isAchieved ? .green : Color.ciFill)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack {
                    reserve
                    Spacer()
                    status
                }
                VStack(alignment: .leading, spacing: 4) {
                    reserve
                    status
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goal.spokenText(deadline: deadline))
    }

    private var iconView: some View {
        Image(systemName: goal.icon.symbolName)
            .font(.title)
            .foregroundStyle(Color.ciFill)
            .accessibilityHidden(true)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(goal.name)
                .font(.headline)
            if let deadline {
                Text("截止日 \(deadline)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saved: some View {
        Text(goal.savedAmount.formatted())
            .font(.title3.bold())
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private var target: some View {
        Text("目標 \(goal.targetAmount.formatted())")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var reserve: some View {
        Text(goal.monthlyReserve > .zero ? "每月預留 \(goal.monthlyReserve.formatted())" : "未設定每月預留")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var status: some View {
        if goal.isAchieved {
            Label("已達成目標", systemImage: "checkmark.seal.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.green)
        } else {
            GlassCapsuleButton(title: "存入", systemImage: "plus", action: deposit)
                .accessibilityIdentifier("goals.deposit.\(goal.id.rawValue)")
        }
    }
}
