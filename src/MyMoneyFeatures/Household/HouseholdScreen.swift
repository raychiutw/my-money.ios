import MyMoneyDomain
import SwiftUI

/// 「家庭」tab:建立或用邀請碼加入;已加入時數字優先(#121):分攤建議大數字、各成員代墊長條圖與平均線、
/// 我的累計代墊／已報銷／待報銷、成員(名字、身分與數字)，邀請與離開降到最下面(parity.md「家庭」、ADR-0004)。
///
/// 永遠顯示這個 tab(HIG:不要隱藏 tab);toolbar 只有頭像按鈕。
struct HouseholdScreen: View {
    @Bindable var model: HouseholdModel
    @State private var isLeaveConfirming = false
    @State private var pendingRemoval: HouseholdMember?
    @State private var reimbursement: ReimbursementModel?
    @State private var skeletonWidth: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum Field: Hashable { case createName, joinCode }
    @FocusState private var focusedField: Field?

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
            // 移除成員是從列上滑出或長按選單觸發的,沒有按鈕可以當錨點:用 alert(置中,不會指到不相關的列，#169)。
            .alert(
                "移除成員",
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
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
            // 跟著實際內容(#204):上次載入時有沒有家庭、幾位成員、有沒有我的代墊統計;沒有記錄時畫成還沒加入。
            switch model.skeletonShape {
            case .notJoined:
                notJoinedSkeleton
            case .joined(let members, let hasMyAdvance):
                joinedSkeleton(members: members, hasMyAdvance: hasMyAdvance)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("無法載入家庭", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                GlassCapsuleButton(title: "重試") {
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

    /// 還沒加入家庭的骨架:兩個表單的形狀(建立家庭、用邀請碼加入),跟真實的 `notJoined` 一樣。
    private var notJoinedSkeleton: some View {
        Form {
            Section("建立家庭") {
                LabeledContent("名稱") { Text("例如：溫馨小家庭") }
                    .skeletonAnnouncement()
                Text("建立").frame(maxWidth: .infinity).padding(.vertical, 10)
                    .skeletonRow()
            }
            .skeletonCell("household.skeleton.notJoined")
            Section("用邀請碼加入") {
                LabeledContent("邀請碼") { Text(verbatim: "FAM-XXXX") }
                    .skeletonRow()
                Text("加入").frame(maxWidth: .infinity).padding(.vertical, 10)
                    .skeletonRow()
            }
        }
    }

    /// 已加入家庭的骨架:家庭名稱、分攤建議與圖、(我的代墊三格磚)、成員列。
    private func joinedSkeleton(members: Int, hasMyAdvance: Bool) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    BigNumber(title: "分攤建議", amount: Skeleton.amount)
                    SkeletonChart(height: 160)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .skeletonAnnouncement()
                .clearListRow()
            }
            if hasMyAdvance {
                Section {
                    NumberTileRow(forcedSingleColumn: tileMemoryChoice) {
                        ForEach(["累計代墊", "已報銷", "待報銷"], id: \.self) { title in
                            NumberTile(title: title, amount: Skeleton.tileAmount, text: Skeleton.tileAmount.formatted())
                                .skeletonCell("household.skeleton.tile.\(title)")
                        }
                    }
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { skeletonWidth = $0 }
                    .clearListRow()
                    .skeletonRow()
                }
            }
            SkeletonSection(title: "成員", count: max(members, 1)) { SkeletonItemRow() }
        }
    }

    private var tileMemoryChoice: Bool? {
        model.skeletonMemory.arrangement(forWidth: skeletonWidth, sizeKey: String(describing: dynamicTypeSize), for: "tiles")
    }

    private var notJoined: some View {
        Form {
            // 建立和加入是兩條互斥的路，各一個 Section、一個欄位、一顆按鈕。欄位要有看得見的標籤，placeholder 只放範例(DESIGN.md「列與欄位」第 8 條，#78)。
            // 按鈕用 bordered prominent:停用時仍然看得出是按鈕，不會跟欄位的 placeholder 一樣只剩灰字(研究 §9)。
            Section("建立家庭") {
                LabeledContent("名稱") {
                    TextField("家庭名稱", text: $model.createName, prompt: Text("例如：溫馨小家庭"))
                        .focused($focusedField, equals: .createName)
                        .accessibilityIdentifier("household.createName")
                }
                .tapToFocus($focusedField, equals: .createName)
                PrimaryCapsuleButton(title: "建立", fillsWidth: true) {
                    Task { await model.create() }
                }
                .disabled(!model.canCreate)
                .accessibilityIdentifier("household.create")
            }

            // 邀請碼的格式只放在 placeholder,不另外寫說明(parity 刻意偏離第 14、43 項)。
            Section("用邀請碼加入") {
                LabeledContent("邀請碼") {
                    TextField("邀請碼", text: $model.joinCode, prompt: Text(verbatim: "FAM-XXXX"))
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .joinCode)
                        .accessibilityIdentifier("household.joinCode")
                }
                .tapToFocus($focusedField, equals: .joinCode)
                PrimaryCapsuleButton(title: "加入", fillsWidth: true) {
                    Task { await model.join() }
                }
                .disabled(!model.canJoin)
                .accessibilityIdentifier("household.join")
            }
        }
    }

    private func joined(_ household: Household) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(household.name)
                        .font(.title3.bold())
                    Text("我的角色：\(household.myRole.title) · \(model.memberCountText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .padding(.horizontal, 8)
                .clearListRow()
                HouseholdHero(model: model)
                    .clearListRow()
            }
            .compactSectionSpacing()

            if let mine = model.myAdvance {
                Section {
                    MyAdvanceTiles(advance: mine, memory: model.skeletonMemory)
                        .clearListRow()
                }
            }

            membersSection

            // 邀請與離開是次要動作，降到最下面;邀請只有家庭管理員看得到(上游 ADR 0013，#132)。
            Section {
                if model.canInvite {
                    Button("邀請家庭成員", systemImage: "person.badge.plus") {
                        Task { await model.invite() }
                    }
                    .disabled(model.isInviting)
                    .accessibilityIdentifier("household.invite")
                }
                Button("離開家庭", role: .destructive) {
                    isLeaveConfirming = true
                }
                .accessibilityIdentifier("household.leave")
                // 確認訊息掛在觸發它的按鈕上(#169)，泡泡的箭頭才指著「離開家庭」。
                .confirmationDialog("離開家庭", isPresented: $isLeaveConfirming, titleVisibility: .visible) {
                    Button("離開", role: .destructive) {
                        Task { await model.leave() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(model.leaveConfirmation)
                }
            }
        }
    }
}

extension HouseholdScreen {
    /// 成員(#121):每位成員一列，只有名字、身分和數字(待報銷);代墊明細就地展開(可以同時展開多位)，
    /// 有待報銷的才有「從共同基金報銷」入口(家庭管理員任何人都有，一般成員只有自己)。家庭管理員往左滑可以移除一般成員。
    private var membersSection: some View {
        Section("成員") {
            let members = model.household?.members ?? []
            ForEach(members) { member in
                let advance = model.advances.first { $0.memberID == member.userID }
                MemberRow(name: member.name, roleTitle: member.role.title, advance: advance)
                    .swipeActions {
                        if model.canRemove(member) {
                            DestructiveSwipeButton("移除", systemImage: "person.badge.minus") { pendingRemoval = member }
                        }
                    }
                    .contextMenu {
                        if model.canRemove(member) {
                            Button("移除", systemImage: "person.badge.minus", role: .destructive) {
                                pendingRemoval = member
                            }
                        }
                    }
                if let advance {
                    advanceControls(advance)
                }
            }
            // 代墊統計裡有、名冊裡沒有的人(例如剛離開家庭的成員):照樣列出，沒有身分。
            ForEach(model.advances.filter { advance in !members.contains { $0.userID == advance.memberID } }) { advance in
                MemberRow(name: advance.memberName, roleTitle: nil, advance: advance)
                advanceControls(advance)
            }
        }
    }

    /// 這位成員的代墊明細(就地展開)與撥款報銷入口。
    @ViewBuilder
    private func advanceControls(_ advance: HouseholdAdvance) -> some View {
        Button(
            model.isShowingDetails(of: advance.memberID)
                ? "收起明細" : "查看代墊明細(\(advance.advanceItems.count + advance.reimbursementItems.count) 筆)",
            systemImage: model.isShowingDetails(of: advance.memberID) ? "chevron.up" : "chevron.down"
        ) {
            model.toggleDetails(of: advance.memberID)
        }
        .accessibilityIdentifier("household.advanceDetails")
        if model.isShowingDetails(of: advance.memberID) {
            AdvanceDetails(advance: advance, dateText: model.dateTimeText)
        }
        if model.canReimburse(advance) {
            Button(Terms.reimburse, systemImage: "arrow.uturn.left.circle") {
                reimbursement = model.makeReimbursement(for: advance)
            }
            .accessibilityLabel("\(Terms.reimburse)給\(advance.memberName)")
            .accessibilityIdentifier("household.reimburse.\(advance.memberID.rawValue)")
        }
    }
}

/// 就地展開的兩份明細：個人代墊消費明細、共同基金撥款沖帳紀錄。
private struct AdvanceDetails: View {
    let advance: HouseholdAdvance
    /// 明細的「日期 時間」(畫面 model 依系統格式產生,時間是台灣時間 HH:mm,#207)。
    let dateText: (CalendarDay, Date?) -> String

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
                    date: item.date, time: item.recordedAt,
                    title: item.note.isEmpty ? item.category.name : "\(item.category.name) · \(item.note)",
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
                    date: item.date, time: item.recordedAt, title: item.note.isEmpty ? "撥款報銷代墊款" : item.note,
                    account: item.accountName, amount: item.amount, isIncome: true
                )
            }
        }
    }

    /// 代墊消費是支出、撥款報銷是收入;VoiceOver 念出收支方向(DESIGN.md「無障礙」)。
    private func detailRow(date: CalendarDay, time: Date?, title: String, account: String, amount: Money, isIncome: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(dateText(date, time)) · \(account)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount.formatted(flow: isIncome ? .inflow : .outflow))
                .monospacedDigit()
                .foregroundStyle(amount.tone(of: isIncome ? .inflow : .outflow).color ?? .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isIncome ? "收入" : "支出") \(amount.spokenText),\(title),\(dateText(date, nil))\(RecordedTime.spokenText(of: time).map { " \($0)" } ?? ""),\(account)")
    }
}

extension ReimbursementModel: Identifiable {}

/// 成員的一列(#121):名稱開頭字、名字、身分(家庭管理員或一般成員)與待報銷的數字(已結清時是「已結清」加勾勾);
/// 家庭公帳代墊的累計與已報銷在我的數字磚(自己)與代墊明細(每個人)。
/// 放不下時(大字級)改成上下堆疊，金額單行。VoiceOver 念一句完整的話，跟以前的代墊摘要列一樣，最後多身分。
private struct MemberRow: View {
    let name: String
    /// 身分(家庭管理員或一般成員);不在名冊裡的人是 `nil`。
    let roleTitle: String?
    /// 這位成員的代墊統計;後端沒有這位成員的紀錄時是 `nil`。
    let advance: HouseholdAdvance?

    /// 圓形頭像跟著字級放大，大字級時開頭字才放得進去。
    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 40

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                avatar
                names
                Spacer(minLength: 8)
                pending
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    avatar
                    names
                }
                // 堆疊時待報銷金額在最下面一行、靠右(#149)。
                pending
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var avatar: some View {
        Text(name.first.map { String($0).uppercased() } ?? "?")
            .font(.headline)
            .frame(width: avatarSize, height: avatarSize)
            .background(Circle().fill(.tint.opacity(0.2)))
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.headline)
            if let roleTitle {
                Text(roleTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pending: some View {
        if let advance {
            if advance.isSettled {
                Label("已結清", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("待報銷")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(advance.pendingReimbursement.formatted(flow: .outflow))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// 例如「小明,有待請款代墊,累計公帳墊付 250 元,已獲撥款報銷 0 元,待報銷 250 元,家庭管理員」;已結清是「已全數結清」。
    private var spokenText: String {
        guard let advance else { return [name, roleTitle].compactMap { $0 }.joined(separator: ",") }
        return ["\(advance.memberName)", advance.isSettled ? "已全數結清" : "有待請款代墊",
                "累計公帳墊付 \(advance.totalAdvanced.spokenText)", "已獲撥款報銷 \(advance.totalReimbursed.spokenText)",
                "待報銷 \(advance.pendingReimbursement.spokenText)", roleTitle]
            .compactMap { $0 }.joined(separator: ",")
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
                SheetConfirmButton("完成", identifier: "household.invitation.done") { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}
