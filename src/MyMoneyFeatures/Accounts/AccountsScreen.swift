import Foundation
import MyMoneyDomain
import SwiftUI

/// 「帳戶」tab:三張統計卡、銀行存款帳戶與信用卡帳戶兩區(parity.md「帳戶」)。
struct AccountsScreen: View {
    @Bindable var model: AccountsModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: Account?
    @State private var pendingRollover: CreditCard?
    @State private var payment: CardPaymentModel?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("帳戶")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("新增銀行存款帳戶", systemImage: "building.columns") {
                                editor = EditorSheet(model.makeEditor(adding: .bank))
                            }
                            Button("新增信用卡", systemImage: "creditcard") {
                                editor = EditorSheet(model.makeEditor(adding: .creditCard))
                            }
                        } label: {
                            Label("新增資金帳戶", systemImage: "plus")
                        }
                        .accessibilityIdentifier("accounts.add")
                    }
                }
                // 第一次出現時載入;之後資料版本改變(任何畫面新增、修改、刪除成功)就重抓。
                .task(id: model.dataVersion.value) {
                    await model.refreshIfStale()
                }
                .sheet(item: $editor) { sheet in
                    AccountEditorView(model: sheet.model)
                }
                .confirmationDialog(
                    "刪除資金帳戶",
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { account in
                    Button("刪除", role: .destructive) {
                        Task { await model.delete(account) }
                    }
                    Button("取消", role: .cancel) {}
                } message: { account in
                    Text(model.deleteConfirmation(for: account))
                }
                .sheet(item: $payment) { payment in
                    CardPaymentView(model: payment)
                }
                .confirmationDialog(
                    "結帳日出帳結轉",
                    isPresented: Binding(get: { pendingRollover != nil }, set: { if !$0 { pendingRollover = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingRollover
                ) { card in
                    Button("結轉") {
                        Task { await model.rollOver(card) }
                    }
                    Button("取消", role: .cancel) {}
                } message: { card in
                    Text(model.rolloverConfirmation(for: card))
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
        }
    }

    /// 編輯 sheet 需要 `Identifiable`。
    private struct EditorSheet: Identifiable {
        let id = UUID()
        let model: AccountEditorModel

        init(_ model: AccountEditorModel) {
            self.model = model
        }
    }

    /// 點一下編輯;往左滑或長按可以刪除(刪除前一律確認：後端刪除無法復原)。
    private func accountRow(_ account: Account, @ViewBuilder label: () -> some View) -> some View {
        Button {
            editor = EditorSheet(model.makeEditor(editing: account))
        } label: {
            label()
        }
        .tint(.primary)
        .swipeActions {
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = account
            }
        }
        .contextMenu {
            Button("編輯", systemImage: "pencil") {
                editor = EditorSheet(model.makeEditor(editing: account))
            }
            Button("刪除", systemImage: "trash", role: .destructive) {
                pendingDeletion = account
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
                Label("無法載入帳戶", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("重試") {
                    Task { await model.load() }
                }
            }
        case .loaded:
            List {
                summarySection
                bankSection
                creditCardSection
            }
            .refreshable { await model.load() }
        }
    }

    private var summarySection: some View {
        Section {
            SummaryRow(
                title: "銀行存款帳戶餘額合計",
                amount: model.bankBalanceTotal ?? .zero,
                detail: model.bankAccountCountText
            )
            SummaryRow(
                title: "待繳卡費總額",
                amount: model.totalCardDue ?? .zero,
                detail: "已出帳待繳 \((model.billedDebtTotal ?? .zero).formatted()) · 未出帳 \((model.unbilledDebtTotal ?? .zero).formatted())"
            )
            SummaryRow(
                title: "淨可用資產",
                amount: model.availableBalance ?? .zero,
                detail: "銀行存款扣掉所有信用卡的待繳卡費總額",
                warnsWhenNegative: true
            )
        }
    }

    private var bankSection: some View {
        Section("銀行存款帳戶(\(model.bankAccounts.count))") {
            if model.bankAccounts.isEmpty {
                Text("尚未新增銀行存款帳戶")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.bankAccounts) { account in
                accountRow(.bank(account)) { BankAccountRow(account: account) }
            }
        }
    }

    private var creditCardSection: some View {
        Section("信用卡(\(model.creditCards.count))") {
            if model.creditCards.isEmpty {
                Text("尚未新增信用卡")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.creditCards) { card in
                accountRow(.creditCard(card)) { CreditCardRow(card: card) }
                // 卡片本身點一下是編輯，所以欠款公私拆解、結帳日提醒與還款放在下一列，不把按鈕塞進按鈕裡。
                CardSettlementRow(
                    card: card,
                    showsRollover: model.showsRollover(card),
                    reminder: model.rolloverReminder(for: card),
                    rollOver: { pendingRollover = card },
                    pay: { payment = model.makePayment(for: card) }
                )
            }
        }
    }
}

/// 給 `.sheet(item:)` 用;class 的 `id` 預設是 `ObjectIdentifier`。
extension CardPaymentModel: Identifiable {}

/// 信用卡帳戶的欠款公私拆解、結帳日出帳結轉的提醒與「信用卡還款沖銷」。
private struct CardSettlementRow: View {
    let card: CreditCard
    let showsRollover: Bool
    let reminder: String
    let rollOver: () -> Void
    let pay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if card.totalDue > .zero {
                VStack(alignment: .leading, spacing: 2) {
                    Text("欠款公私拆解：家庭公帳 \(card.sharedDebtPercentText)")
                        .font(.footnote.bold())
                    Text("家庭公帳 \(card.sharedDebt.formatted()) · 個人私帳 \(card.personalDebt.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "欠款公私拆解，家庭公帳佔 \(card.sharedDebtPercentText),家庭公帳 \(card.sharedDebt.spokenText),個人私帳 \(card.personalDebt.spokenText)"
                )
            }
            if showsRollover {
                HStack {
                    Label(reminder, systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("一鍵出帳", action: rollOver)
                        .buttonStyle(.borderless)
                        .font(.footnote.bold())
                        .accessibilityIdentifier("accounts.rollover.\(card.id.rawValue)")
                }
            }
            Button("信用卡還款沖銷", systemImage: "arrow.left.arrow.right", action: pay)
                .buttonStyle(.borderless)
                .disabled(card.totalDue <= .zero)
                .accessibilityIdentifier("accounts.pay.\(card.id.rawValue)")
        }
    }
}

private struct BankAccountRow: View {
    let account: BankAccount

    var body: some View {
        HStack(spacing: 12) {
            AccountColorMark(hex: account.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if account.isJointFund {
                    Label("家庭共同基金", systemImage: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(account.balance.formatted())
                .monospacedDigit()
                .foregroundStyle(account.balance < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.name)\(account.isJointFund ? ",家庭共同基金" : ""),餘額 \(account.balance.spokenText)")
    }
}

private struct CreditCardRow: View {
    let card: CreditCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AccountColorMark(hex: card.colorHex)
                Text(card.name)
                    .font(.headline)
                Spacer()
                if let limit = card.creditLimit {
                    Text("額度 \(limit.formatted())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            LabeledContent("已出帳待繳金額", value: card.billedDebt.formatted())
                .monospacedDigit()
            LabeledContent("未出帳金額", value: card.unbilledDebt.formatted())
                .monospacedDigit()
            if let dates = billingDates {
                Text(dates)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let remaining = card.remainingCredit {
                HStack(spacing: 4) {
                    if card.isLowOnCredit {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    Text("剩餘額度 \(remaining.formatted())\(card.isLowOnCredit ? "(額度不足)" : "")")
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(card.isLowOnCredit ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// 例如「結帳日：每月 15 號 · 繳款日：每月 5 號」。
    private var billingDates: String? {
        let parts = [
            card.statementDay.map { "結帳日：每月 \($0) 號" },
            card.paymentDueDay.map { "繳款日：每月 \($0) 號" },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 使用者選的資金帳戶代表色。只是輔助辨識，不是唯一的資訊(DESIGN.md「顏色」)。
private struct AccountColorMark: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 6, height: 28)
            .accessibilityHidden(true)
    }
}
