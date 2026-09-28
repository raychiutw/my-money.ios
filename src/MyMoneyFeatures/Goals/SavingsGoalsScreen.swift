import Foundation
import MyMoneyDomain
import SwiftUI

/// 規劃 → 儲蓄目標：三張統計卡，有截止日與沒有截止日兩組(parity.md「儲蓄目標」)。
struct SavingsGoalsScreen: View {
    @Bindable var model: SavingsGoalsModel
    @State private var sheet: ActiveSheet?
    @State private var pendingDeletion: SavingsGoal?

    var body: some View {
        content
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
            .confirmationDialog(
                "刪除儲蓄目標",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入儲蓄目標", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            List {
                Section {
                    SummaryRow(title: "已存金額合計", amount: model.totalSaved, detail: "所有目標累計已存的金額")
                    SummaryRow(title: "目標金額合計", amount: model.totalTarget, detail: "整體達成率 \(model.overallRateText)")
                    SummaryRow(title: "每月預留合計", amount: model.totalMonthlyReserve, detail: "每月從真實可支配現金中扣除")
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

    @ViewBuilder
    private func goalSection(_ title: String, goals: [SavingsGoal]) -> some View {
        if !goals.isEmpty {
            Section("\(title)(\(goals.count))") {
                ForEach(goals) { goal in
                    SavingsGoalRow(goal: goal) {
                        sheet = model.makeDeposit(for: goal).map(ActiveSheet.deposit)
                    }
                    .swipeActions {
                        Button("刪除", systemImage: "trash", role: .destructive) {
                            pendingDeletion = goal
                        }
                        Button("編輯", systemImage: "pencil") {
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

/// 一個儲蓄目標：emoji、名稱、截止日、已存金額、目標金額與百分比、進度、每月預留，以及「存入」。
/// 已達成時用成功色，並停用存入(parity 刻意偏離第 6 項)。
private struct SavingsGoalRow: View {
    let goal: SavingsGoal
    let deposit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(goal.emoji)
                    .font(.title)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.headline)
                    if let deadline = goal.deadline {
                        Text("截止日 \(deadline.slashText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(goal.savedAmount.formatted())
                    .font(.title3.bold())
                    .monospacedDigit()
                Spacer()
                Text("目標 \(goal.targetAmount.formatted())(\(goal.percentText))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: goal.progress)
                .tint(goal.isAchieved ? .green : .accentColor)
                .accessibilityHidden(true)
            HStack {
                Text(goal.monthlyReserve > .zero ? "每月預留 \(goal.monthlyReserve.formatted())" : "未設定每月預留")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if goal.isAchieved {
                    Label("已達成目標", systemImage: "checkmark.seal.fill")
                        .font(.footnote.bold())
                        .foregroundStyle(.green)
                } else {
                    Button("存入", systemImage: "plus.circle.fill", action: deposit)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("goals.deposit.\(goal.id.rawValue)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [goal.name, "已存 \(goal.savedAmount.spokenText)", "目標 \(goal.targetAmount.spokenText)", goal.percentText]
        if let deadline = goal.deadline { parts.append("截止日 \(deadline.slashText)") }
        if goal.isAchieved { parts.append("已達成目標") }
        return parts.joined(separator: ",")
    }
}
