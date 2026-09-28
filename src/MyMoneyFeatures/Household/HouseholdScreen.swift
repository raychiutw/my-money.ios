import MyMoneyDomain
import SwiftUI

/// 帳號 sheet → 家庭：建立或用邀請碼加入;已加入時是家庭資訊、邀請、成員名冊、離開(parity.md「家庭」)。
struct HouseholdScreen: View {
    @Bindable var model: HouseholdModel
    @State private var isLeaveConfirming = false
    @State private var pendingRemoval: HouseholdMember?
    @State private var reimbursement: ReimbursementModel?

    var body: some View {
        content
            .skeletonTransition(value: model.phase)
            .navigationTitle("家庭群組")
            .inlineNavigationTitle()
            .task { await model.load() }
            .sheet(item: $model.invitation) { invitation in
                InvitationSheet(invitation: invitation)
            }
            .confirmationDialog(
                "離開家庭群組",
                isPresented: $isLeaveConfirming,
                titleVisibility: .visible
            ) {
                Button("離開", role: .destructive) {
                    Task { await model.leave() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(model.leaveConfirmation)
            }
            .confirmationDialog(
                "移除成員",
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemoval
            ) { member in
                Button("移除", role: .destructive) {
                    Task { await model.remove(member) }
                }
                Button("取消", role: .cancel) {}
            } message: { member in
                Text(model.removeConfirmation(for: member))
            }
            .alert(
                "無法完成",
                isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(model.alertMessage ?? "")
            }
            .alert(
                "完成",
                isPresented: Binding(get: { model.noticeMessage != nil }, set: { if !$0 { model.noticeMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(model.noticeMessage ?? "")
            }
            .sheet(item: $reimbursement) { reimbursement in
                ReimbursementView(model: reimbursement) { message in
                    model.noticeMessage = message
                    Task { await model.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            List {
                SkeletonSection(count: 1, announces: true) { SkeletonItemRow() }
                SkeletonSection(title: "家庭成員", count: 2) { SkeletonItemRow() }
                SkeletonSection(title: "家庭公帳代墊與報銷", count: 2) { SkeletonItemRow() }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入家庭群組", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            if let household = model.household {
                joined(household)
            } else {
                notJoined
            }
        }
    }

    private var notJoined: some View {
        Form {
            Section {
                TextField("家庭群組名稱", text: $model.createName, prompt: Text("例如：溫馨小家庭"))
                    .accessibilityIdentifier("household.createName")
                Button("建立家庭群組") {
                    Task { await model.create() }
                }
                .disabled(!model.canCreate)
                .accessibilityIdentifier("household.create")
            } header: {
                Text("建立家庭群組")
            } footer: {
                Text("建立之後，你是這個家庭群組的管理員，可以邀請家庭成員加入。")
            }

            Section {
                TextField("邀請碼", text: $model.joinCode, prompt: Text(verbatim: "FAM-XXXX"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("household.joinCode")
                Button("加入家庭群組") {
                    Task { await model.join() }
                }
                .disabled(!model.canJoin)
                .accessibilityIdentifier("household.join")
            } header: {
                Text("用邀請碼加入")
            } footer: {
                Text("輸入家庭成員分享的邀請碼，格式是 FAM-XXXX。")
            }
        }
    }

    private func joined(_ household: Household) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(household.name)
                        .font(.title3.bold())
                    Text("我的角色：\(household.myRole.title) · \(model.memberCountText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Button("邀請家庭成員", systemImage: "person.badge.plus") {
                    Task { await model.invite() }
                }
                .disabled(model.isInviting)
                .accessibilityIdentifier("household.invite")
            }

            advancesSection

            Section("家庭成員名冊") {
                ForEach(household.members) { member in
                    MemberRow(member: member)
                        .swipeActions {
                            if model.canRemove(member) {
                                Button("移除", systemImage: "person.badge.minus", role: .destructive) {
                                    pendingRemoval = member
                                }
                            }
                        }
                        .contextMenu {
                            if model.canRemove(member) {
                                Button("移除", systemImage: "person.badge.minus", role: .destructive) {
                                    pendingRemoval = member
                                }
                            }
                        }
                }
            }

            Section {
                Button("離開家庭群組", role: .destructive) {
                    isLeaveConfirming = true
                }
                .accessibilityIdentifier("household.leave")
            }
        }
    }
}

extension HouseholdScreen {
    /// 家庭公帳代墊與報銷(web 的「家庭公帳代墊與報銷中心」):每位成員一列，明細就地展開，可以同時展開多位。
    private var advancesSection: some View {
        Section {
            if model.advances.isEmpty {
                Text("暫無公帳代墊款紀錄")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.advances) { advance in
                AdvanceSummaryRow(advance: advance)
                Button(
                    model.isShowingDetails(of: advance.memberID)
                        ? "收起明細" : "查看代墊明細(\(advance.advanceItems.count + advance.reimbursementItems.count) 筆)",
                    systemImage: model.isShowingDetails(of: advance.memberID) ? "chevron.up" : "chevron.down"
                ) {
                    model.toggleDetails(of: advance.memberID)
                }
                .accessibilityIdentifier("household.advanceDetails")
                if model.isShowingDetails(of: advance.memberID) {
                    AdvanceDetails(advance: advance)
                }
                if model.canReimburse(advance) {
                    Button("從共同基金報銷", systemImage: "arrow.uturn.left.circle") {
                        reimbursement = model.makeReimbursement(for: advance)
                    }
                    .accessibilityLabel("從共同基金報銷給\(advance.memberName)")
                    .accessibilityIdentifier("household.reimburse.\(advance.memberID.rawValue)")
                }
            }
        } header: {
            Text("家庭公帳代墊與報銷")
        } footer: {
            Text("只有用個人帳戶(個人私帳、私卡或個人現金錢包)付的家庭公帳支出才算代墊;由家庭共同基金直接付的不算。")
        }
    }
}

/// 一位成員的代墊摘要：名稱、結清狀態、累計代墊與已報銷、待報銷金額。
private struct AdvanceSummaryRow: View {
    let advance: HouseholdAdvance

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(advance.memberName)
                        .font(.headline)
                    Label(advance.isSettled ? "已全數結清" : "有待請款代墊", systemImage: advance.isSettled ? "checkmark.circle" : "clock")
                        .font(.footnote)
                        .foregroundStyle(advance.isSettled ? .green : .orange)
                }
                Text("累計公帳墊付 \(advance.totalAdvanced.formatted()) · 已獲撥款報銷 \(advance.totalReimbursed.formatted())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("待報銷")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(advance.pendingReimbursement.formatted())
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(advance.isSettled ? .green : .red)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(advance.memberName),\(advance.isSettled ? "已全數結清" : "有待請款代墊"),"
                + "累計公帳墊付 \(advance.totalAdvanced.spokenText),已獲撥款報銷 \(advance.totalReimbursed.spokenText),"
                + "待報銷 \(advance.pendingReimbursement.spokenText)"
        )
    }
}

/// 就地展開的兩份明細：個人代墊消費明細、共同基金撥款沖帳紀錄。
private struct AdvanceDetails: View {
    let advance: HouseholdAdvance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("個人代墊消費明細(\(advance.advanceItems.count) 筆)")
                .font(.subheadline.bold())
            if advance.advanceItems.isEmpty {
                Text("尚未有任何個人代墊公帳消費紀錄。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(advance.advanceItems) { item in
                detailRow(
                    date: item.date, title: item.note.isEmpty ? item.category.name : "\(item.category.name) · \(item.note)",
                    account: item.accountName, amount: item.amount, isIncome: false
                )
            }
            Text("共同基金撥款沖帳紀錄(\(advance.reimbursementItems.count) 筆)")
                .font(.subheadline.bold())
                .padding(.top, 4)
            if advance.reimbursementItems.isEmpty {
                Text("尚未有自共同基金撥款報銷之歷史沖帳紀錄。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(advance.reimbursementItems) { item in
                detailRow(
                    date: item.date, title: item.note.isEmpty ? "撥款報銷代墊款" : item.note,
                    account: item.accountName, amount: item.amount, isIncome: true
                )
            }
        }
    }

    /// 代墊消費是支出、撥款報銷是收入;VoiceOver 念出收支方向(DESIGN.md「無障礙」)。
    private func detailRow(date: CalendarDay, title: String, account: String, amount: Money, isIncome: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(date.slashText) · \(account)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(isIncome ? "+" : "-")\(amount.formatted())")
                .monospacedDigit()
                .foregroundStyle(isIncome ? .green : .red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isIncome ? "收入" : "支出") \(amount.spokenText),\(title),\(date.slashText),\(account)")
    }
}

extension ReimbursementModel: Identifiable {}

/// 名冊的一個人：名稱開頭字、名稱、角色、email、加入日期。
private struct MemberRow: View {
    let member: HouseholdMember

    var body: some View {
        HStack(spacing: 12) {
            Text(member.initial)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.tint.opacity(0.2)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                    Text(member.role.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(member.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("加入日期 \(member.joinedDateText())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 剛產生的邀請碼：邀請碼、有效期限(當地格式)與「複製」。
private struct InvitationSheet: View {
    let invitation: HouseholdInvitation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.copiedFeedbackDuration) private var copiedFeedbackDuration
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invitation.code)
                        .font(.largeTitle.monospaced().bold())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("household.invitationCode")
                    Button(isCopied ? "已複製" : "複製", systemImage: isCopied ? "checkmark" : "doc.on.doc") {
                        copyToPasteboard(invitation.code)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: copiedFeedbackDuration)
                            isCopied = false
                        }
                    }
                    .accessibilityIdentifier("household.copy")
                } footer: {
                    Text("有效期限：\(invitation.expiresAt.formatted(date: .long, time: .shortened))。請家庭成員登入後，在「帳號 → 家庭群組」輸入這組邀請碼(格式是 FAM-XXXX)。")
                }
            }
            .navigationTitle("邀請家庭成員")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
