import MyMoneyDomain
import SwiftUI

/// 帳號 sheet → 家庭：建立或用邀請碼加入;已加入時是家庭資訊、邀請、成員名冊、離開(parity.md「家庭」)。
struct HouseholdScreen: View {
    @Bindable var model: HouseholdModel
    @State private var isLeaveConfirming = false
    @State private var pendingRemoval: HouseholdMember?

    var body: some View {
        content
            .navigationTitle("家庭")
            .inlineNavigationTitle()
            .task { await model.load() }
            .sheet(item: $model.invitation) { invitation in
                InvitationSheet(invitation: invitation)
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
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Section {
                TextField("家庭名稱", text: $model.createName, prompt: Text("例如：溫馨小家庭"))
                    .accessibilityIdentifier("household.createName")
                Button("建立家庭") {
                    Task { await model.create() }
                }
                .disabled(!model.canCreate)
                .accessibilityIdentifier("household.create")
            } header: {
                Text("建立家庭")
            } footer: {
                Text("建立之後，你是這個家庭群組的管理員，可以邀請家人加入。")
            }

            Section {
                TextField("邀請碼", text: $model.joinCode, prompt: Text(verbatim: "FAM-XXXX"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("household.joinCode")
                Button("加入家庭") {
                    Task { await model.join() }
                }
                .disabled(!model.canJoin)
                .accessibilityIdentifier("household.join")
            } header: {
                Text("用邀請碼加入")
            } footer: {
                Text("輸入家人分享的邀請碼，格式是 FAM-XXXX。")
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
                Button("邀請家人", systemImage: "person.badge.plus") {
                    Task { await model.invite() }
                }
                .accessibilityIdentifier("household.invite")
            }

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
                Button("離開家庭", role: .destructive) {
                    isLeaveConfirming = true
                }
                .accessibilityIdentifier("household.leave")
            }
        }
    }
}

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(member.email)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("加入日期 \(member.joinedDateText())")
                    .font(.caption)
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
                            try? await Task.sleep(for: .seconds(2))
                            isCopied = false
                        }
                    }
                    .accessibilityIdentifier("household.copy")
                } footer: {
                    Text("有效期限：\(invitation.expiresAt.formatted(date: .long, time: .shortened))。請家人登入後，在「帳號 → 家庭」輸入這組邀請碼(格式是 FAM-XXXX)。")
                }
            }
            .navigationTitle("邀請家人")
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
