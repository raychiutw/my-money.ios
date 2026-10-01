import MyMoneyDomain
import SwiftUI

/// 「家庭」tab:建立或用邀請碼加入;已加入時是家庭資訊、邀請、成員名冊、離開(parity.md「家庭」、ADR-0004)。
///
/// 永遠顯示這個 tab(HIG:不要隱藏 tab);toolbar 只有頭像按鈕。
struct HouseholdScreen: View {
    @Bindable var model: HouseholdModel
    @State private var isLeaveConfirming = false
    @State private var pendingRemoval: HouseholdMember?
    @State private var reimbursement: ReimbursementModel?

    var body: some View {
        NavigationStack {
            screen
        }
    }

    private var screen: some View {
        content
            .skeletonTransition(value: model.phase)
            .tabRootNavigation("家庭")
            .toolbar {
                AccountToolbarItem()
            }
            .task { await model.load() }
            .sheet(item: $model.invitation) { invitation in
                InvitationSheet(invitation: invitation, expiry: model.expiryText(of: invitation))
            }
            .confirmationDialog(
                "離開家庭",
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
                Label("無法載入家庭", systemImage: "exclamationmark.triangle")
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
            // 建立和加入是兩條互斥的路，各一個 Section、一個欄位、一顆按鈕。欄位要有看得見的標籤，placeholder 只放範例(DESIGN.md「列與欄位」第 8 條，#78)。
            // 按鈕用 bordered prominent:停用時仍然看得出是按鈕，不會跟欄位的 placeholder 一樣只剩灰字(研究 §9)。
            Section("建立家庭") {
                LabeledContent("名稱") {
                    TextField("家庭名稱", text: $model.createName, prompt: Text("例如：溫馨小家庭"))
                        .accessibilityIdentifier("household.createName")
                }
                Button("建立") {
                    Task { await model.create() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!model.canCreate)
                .accessibilityIdentifier("household.create")
            }

            // 邀請碼的格式只放在 placeholder,不另外寫說明(parity 刻意偏離第 14、43 項)。
            Section("用邀請碼加入") {
                LabeledContent("邀請碼") {
                    TextField("邀請碼", text: $model.joinCode, prompt: Text(verbatim: "FAM-XXXX"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("household.joinCode")
                }
                Button("加入") {
                    Task { await model.join() }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!model.canJoin)
                .accessibilityIdentifier("household.join")
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
                    MemberRow(member: member, joined: model.joinedDateText(of: member))
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
                Button("離開家庭", role: .destructive) {
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
        Section("家庭公帳代墊與報銷") {
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
                    AdvanceDetails(advance: advance, dateText: model.dateText)
                }
                if model.canReimburse(advance) {
                    Button("從共同基金報銷", systemImage: "arrow.uturn.left.circle") {
                        reimbursement = model.makeReimbursement(for: advance)
                    }
                    .accessibilityLabel("從共同基金報銷給\(advance.memberName)")
                    .accessibilityIdentifier("household.reimburse.\(advance.memberID.rawValue)")
                }
            }
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
    /// 明細的日期(畫面 model 依系統格式產生)。
    let dateText: (CalendarDay) -> String

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
                Text("\(dateText(date)) · \(account)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(isIncome ? "+" : "-")\(amount.formatted())")
                .monospacedDigit()
                .foregroundStyle(isIncome ? .green : .red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isIncome ? "收入" : "支出") \(amount.spokenText),\(title),\(dateText(date)),\(account)")
    }
}

extension ReimbursementModel: Identifiable {}

/// 名冊的一個人：名稱開頭字、名稱、角色、email、加入日期。
private struct MemberRow: View {
    let member: HouseholdMember
    /// 加入日期(畫面 model 依系統格式產生)。
    let joined: String

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
                Text("加入日期 \(joined)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 剛產生的邀請碼：邀請碼、有效期限(系統格式，台灣時間)與「複製」。
private struct InvitationSheet: View {
    let invitation: HouseholdInvitation
    /// 有效期限(畫面 model 依系統格式產生，台灣時間)。
    let expiry: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invitation.code)
                        .font(.largeTitle.monospaced().bold())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("household.invitationCode")
                    CopyButton(text: invitation.code)
                        .accessibilityIdentifier("household.copy")
                } footer: {
                    // 只留有效期限(資料);怎麼使用邀請碼不另外說明(DESIGN.md「說明文字」)。
                    Text("有效期限：\(expiry)")
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
