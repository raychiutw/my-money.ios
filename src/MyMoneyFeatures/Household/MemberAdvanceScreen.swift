import MyMoneyDomain
import SwiftUI

/// 一位成員的代墊詳細頁(#246):成員列點進來。依 Apple 的慣例(Lists and tables:列只放標題、細節放詳細頁，可點的列用 disclosure indicator),
/// 沿用信用卡詳細頁的版型:每個欄位一列，Section「代墊統計」「待報銷代墊明細」「共同基金撥款沖帳紀錄」;
/// 主要動作「報銷沖帳」在 toolbar 的 trailing(#248,HIG Toolbars:對目前畫面的操作放 toolbar、只指定一個 primary action 並放在 trailing;
/// 難用符號表達的動作可以用文字,跟信用卡詳細頁的「編輯」同一慣例)，不在頁面最底下要捲過整串明細才找得到。
///
/// 資料來自 `HouseholdModel`(報銷之後重新載入就會更新);報銷成功時在這一頁顯示後端的訊息，按「好」之後回到家庭頁。
struct MemberAdvanceScreen: View {
    @Bindable var model: HouseholdModel
    let memberID: UserID
    @State private var reimbursement: ReimbursementModel?
    /// 待報銷／已結清兩個分頁(上游 ADR 0027)。
    @State private var tab: AdvanceTab = .pending
    /// 標記已額外處理的勾選模式。
    @State private var isSelecting = false
    @State private var selectedIDs: Set<TransactionID> = []
    @State private var isConfirmingMarkSettled = false
    @State private var settledToUnlink: SettledAdvanceItem?
    /// 解除報銷、標記已額外處理成功時留在這一頁(報銷成功才回到家庭頁)。
    @State private var staysAfterNotice = false
    @Environment(\.dismiss) private var dismiss

    private enum AdvanceTab: Hashable {
        case pending
        case settled
    }

    var body: some View {
        Group {
            if let advance = model.advance(of: memberID) {
                details(advance)
            } else {
                ContentUnavailableView("沒有代墊紀錄", systemImage: "tray")
            }
        }
        .navigationTitle(model.advance(of: memberID)?.memberName ?? "")
        .inlineNavigationTitle()
        .toolbar {
            // 家庭管理員任何人都有，一般成員只有自己的;已結清的不能報銷。
            if let advance = model.advance(of: memberID), model.canReimburse(advance) {
                ToolbarItem(placement: .primaryAction) {
                    Button(Terms.reimburse) {
                        reimbursement = model.makeReimbursement(for: advance)
                    }
                    .accessibilityLabel("\(Terms.reimburse)給\(advance.memberName)")
                    .accessibilityIdentifier("household.reimburse.\(advance.memberID.rawValue)")
                }
            }
            // 標記已額外處理(上游 `fe90634`):已經在家庭外處理掉的代墊，直接移出待報銷;勾選模式裡換成「取消」與「標記」。
            if let advance = model.advance(of: memberID), model.canMarkSettled(advance) {
                if isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isSelecting = false; selectedIDs = [] }
                            .accessibilityIdentifier("advance.selectCancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("標記") { isConfirmingMarkSettled = true }
                            .disabled(selectedIDs.isEmpty)
                            .accessibilityIdentifier("advance.markSettled")
                    }
                } else if tab == .pending {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("標記已額外處理…", systemImage: "checkmark.circle") { isSelecting = true }
                            .accessibilityIdentifier("advance.beginSelecting")
                    }
                }
            }
        }
        // 後端的訊息(報銷成功):訊息掛在這一頁，sheet 關掉之後才不會被頁面轉場吃掉;按「好」回到家庭頁。
        .alert(
            "完成",
            isPresented: Binding(
                get: { model.noticeMessage != nil },
                set: {
                    if !$0 {
                        model.noticeMessage = nil
                        // 旗標由每個動作開始時設定(報銷 false、解除與標記 true);setter 可能被呼叫不只一次，所以這裡不重設。
                        if !staysAfterNotice { dismiss() }
                    }
                }
            )
        ) {
            Button("好") {}
        } message: {
            Text(model.noticeMessage ?? "")
        }
    }

    private func details(_ advance: HouseholdAdvance) -> some View {
        List {
            Section("代墊統計") {
                AmountRow(title: "累計代墊", amount: .plain(advance.totalAdvanced))
                AmountRow(title: "已報銷", amount: .plain(advance.totalReimbursed))
                if let status = model.pendingStatusText(of: advance) {
                    // 退款比待報銷的支出多:留待之後的代墊自動沖抵,不能撥款報銷(上游 ADR 0029)。
                    LabeledContent("待報銷") {
                        Text("\(status) \((Money.zero - advance.pendingReimbursement).formatted())")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("待報銷")
                    .accessibilityValue("\(status) \((Money.zero - advance.pendingReimbursement).spokenText)")
                    .accessibilityIdentifier("advance.offsetPending")
                } else {
                    AmountRow(
                        title: "待報銷",
                        amount: advance.pendingReimbursement > .zero ? .outflow(advance.pendingReimbursement) : .plain(advance.pendingReimbursement)
                    )
                }
                // 累計撥款比對應到明細的多:獨立揭示的溢撥預收款，不會吞掉之後新增的代墊(上游 ADR 0027)。
                if advance.unlinkedReimbursed > .zero {
                    AmountRow(title: "家庭基金溢撥／預收款", amount: .plain(advance.unlinkedReimbursed))
                        .accessibilityIdentifier("advance.surplus")
                }
            }

            Section {
                Picker("明細", selection: $tab) {
                    Text("待報銷明細").tag(AdvanceTab.pending)
                    Text("已結清明細").tag(AdvanceTab.settled)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("advance.tab")
                .onChange(of: tab) { _, _ in isSelecting = false; selectedIDs = [] }
            }
            .listRowBackground(Color.clear)

            if tab == .pending {
                pendingSection(advance)
            } else {
                settledSection(advance)
            }

            Section("共同基金撥款沖帳紀錄(\(advance.reimbursementItems.count) 筆)") {
                if advance.reimbursementItems.isEmpty {
                    Text("尚未有自共同基金撥款報銷之歷史沖帳紀錄。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(advance.reimbursementItems) { item in
                    detailRow(
                        date: item.date, time: item.recordedAt, title: item.note.isEmpty ? "撥款報銷代墊款" : item.note,
                        account: item.accountName, extra: nil, amount: item.amount, isIncome: true
                    )
                }
            }
        }
        .sheet(item: $reimbursement) { reimbursement in
            ReimbursementView(model: reimbursement) { message in
                staysAfterNotice = false
                model.noticeMessage = message
                Task { await model.load() }
            }
        }
        .confirmationDialog("標記已額外處理", isPresented: $isConfirmingMarkSettled, titleVisibility: .visible) {
            Button("標記 \(selectedIDs.count) 筆") {
                let ids = Array(selectedIDs)
                staysAfterNotice = true
                isSelecting = false
                selectedIDs = []
                Task { await model.markSettled(ids, for: advance) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這些代墊會移出待報銷、記為已額外處理，不會動共同基金。之後可以在已結清明細解除。")
        }
        .confirmationDialog(
            "解除報銷", isPresented: Binding(get: { settledToUnlink != nil }, set: { if !$0 { settledToUnlink = nil } }),
            titleVisibility: .visible, presenting: settledToUnlink
        ) { settled in
            Button("解除報銷") {
                staysAfterNotice = true
                Task { await model.unlink(settled) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("這筆明細會退回待報銷。")
        }
    }

    private func pendingSection(_ advance: HouseholdAdvance) -> some View {
        Section("待報銷代墊明細(\(advance.advanceItems.count) 筆)") {
            if advance.advanceItems.isEmpty {
                Text("尚未有任何個人代墊公帳消費紀錄。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(advance.advanceItems) { item in
                if isSelecting {
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(item.id) },
                        set: { if $0 { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) } }
                    )) {
                        detailRow(
                            date: item.date, time: item.recordedAt, title: item.displayTitle, account: item.accountName,
                            extra: item.billingText, amount: item.amount, isIncome: item.kind == .refund
                        )
                    }
                    .tint(Color.ciFill)
                    .accessibilityIdentifier("advance.select.\(item.id.rawValue)")
                } else {
                    detailRow(
                        date: item.date, time: item.recordedAt, title: item.displayTitle, account: item.accountName,
                        extra: item.billingText, amount: item.amount, isIncome: item.kind == .refund
                    )
                    .accessibilityIdentifier("advance.pending.\(item.id.rawValue)")
                }
            }
        }
    }

    private func settledSection(_ advance: HouseholdAdvance) -> some View {
        Section("已結清代墊明細(\(advance.settledItems.count) 筆)") {
            if advance.settledItems.isEmpty {
                Text("還沒有已結清的代墊明細。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(advance.settledItems) { settled in
                detailRow(
                    date: settled.item.date, time: settled.item.recordedAt, title: settled.item.displayTitle,
                    account: settled.item.accountName, extra: model.settlementText(of: settled, in: advance),
                    amount: settled.item.amount, isIncome: settled.item.kind == .refund
                )
                .accessibilityIdentifier("advance.settled.\(settled.id.rawValue)")
                .trailingMoreMenu(
                    label: "\(settled.item.displayTitle)的更多動作", identifier: "advance.more.\(settled.id.rawValue)",
                    isShown: model.canUnlink(settled, in: advance)
                ) {
                    Button("解除報銷", systemImage: "link.badge.minus", role: .destructive) { settledToUnlink = settled }
                }
                .swipeActions {
                    if model.canUnlink(settled, in: advance) {
                        DestructiveSwipeButton("解除報銷", systemImage: "link.badge.minus") { settledToUnlink = settled }
                    }
                }
                .accessibilityAction(named: "解除報銷") {
                    if model.canUnlink(settled, in: advance) { settledToUnlink = settled }
                }
            }
        }
    }

    /// 代墊消費是支出、撥款報銷是收入;VoiceOver 念出收支方向(DESIGN.md「無障礙」)。
    private func detailRow(
        date: CalendarDay, time: Date?, title: String, account: String, extra: String?, amount: Money, isIncome: Bool
    ) -> some View {
        MemberDetailRow(
            title: title, units: ["\(model.dateTimeText(date, time))", account] + [extra].compactMap { $0 },
            amount: isIncome ? .inflow(amount) : .outflow(amount)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isIncome ? "收入" : "支出") \(amount.spokenText),\(title),\(model.dateTimeText(date, nil))\(RecordedTime.spokenText(of: time).map { " \($0)" } ?? ""),\(account)\(extra.map { ",\($0)" } ?? "")")
    }
}

/// 成員詳細頁的項目列:標題、次要文字(日期時間・帳戶，每段不拆開)，金額在右邊跟標題同一行;
/// 無障礙字級改上下堆疊、金額最後一行靠右。結構只跟字級走、不跟資料長短走(#248)。
private struct MemberDetailRow: View {
    let title: String
    let units: [String]
    let amount: AmountPresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                texts
                AmountText(amount).monospacedDigit().lineLimit(1).fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                texts
                Spacer(minLength: 0)
                AmountText(amount).monospacedDigit().lineLimit(1).fixedSize()
            }
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            WrappingUnits(units: units)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

extension ReimbursementModel: Identifiable {}
