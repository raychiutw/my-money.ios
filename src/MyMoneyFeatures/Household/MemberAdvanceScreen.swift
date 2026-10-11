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
    @State private var isLeaveConfirming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let advance = model.advance(of: memberID) {
                details(advance)
            } else if model.isCurrentUser(memberID) {
                // 自己還沒有代墊紀錄:仍要有「離開家庭」。
                List { leaveSection }
            } else {
                ContentUnavailableView("沒有代墊紀錄", systemImage: "tray")
            }
        }
        .navigationTitle(model.memberName(of: memberID))
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
        }
        // 離開家庭之後家庭沒了，這一頁跟著退回根頁(根頁會換成建立／加入的畫面)。
        .onChange(of: model.household == nil) { _, isGone in
            if isGone { dismiss() }
        }
        // 後端的訊息(報銷成功):訊息掛在這一頁，sheet 關掉之後才不會被頁面轉場吃掉;按「好」回到家庭頁。
        .alert(
            "完成",
            isPresented: Binding(
                get: { model.noticeMessage != nil },
                set: { if !$0 { model.noticeMessage = nil; dismiss() } }
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
                AmountRow(
                    title: "待報銷",
                    amount: advance.pendingReimbursement > .zero ? .outflow(advance.pendingReimbursement) : .plain(advance.pendingReimbursement)
                )
            }

            Section("待報銷代墊明細(\(advance.advanceItems.count) 筆)") {
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
                        account: item.accountName, amount: item.amount, isIncome: true
                    )
                }
            }

            if model.isCurrentUser(memberID) { leaveSection }
        }
        .sheet(item: $reimbursement) { reimbursement in
            ReimbursementView(model: reimbursement) { message in
                model.noticeMessage = message
                Task { await model.load() }
            }
        }
    }

    /// 離開家庭(#248):破壞性動作放在自己的成員頁最下面並先確認，確認訊息掛在按鈕上(#169)，泡泡的箭頭才指著它。
    private var leaveSection: some View {
        Section {
            Button("離開家庭", role: .destructive) { isLeaveConfirming = true }
                .accessibilityIdentifier("household.leave")
                .confirmationDialog("離開家庭", isPresented: $isLeaveConfirming, titleVisibility: .visible) {
                    Button("離開", role: .destructive) { Task { await model.leave() } }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(model.leaveConfirmation)
                }
        }
    }

    /// 代墊消費是支出、撥款報銷是收入;VoiceOver 念出收支方向(DESIGN.md「無障礙」)。
    private func detailRow(date: CalendarDay, time: Date?, title: String, account: String, amount: Money, isIncome: Bool) -> some View {
        MemberDetailRow(
            title: title, units: ["\(model.dateTimeText(date, time))", account],
            amount: isIncome ? .inflow(amount) : .outflow(amount)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isIncome ? "收入" : "支出") \(amount.spokenText),\(title),\(model.dateTimeText(date, nil))\(RecordedTime.spokenText(of: time).map { " \($0)" } ?? ""),\(account)")
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
