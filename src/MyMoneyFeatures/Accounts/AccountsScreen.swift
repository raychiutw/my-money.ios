import Foundation
import MyMoneyDomain
import SwiftUI

/// 「帳戶」tab:三張統計卡、銀行存款帳戶與信用卡帳戶兩區(parity.md「帳戶」)。
struct AccountsScreen: View {
    @Bindable var model: AccountsModel
    @State private var editor: EditorSheet?
    @State private var pendingDeletion: Account?

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
                .alert(
                    "無法刪除",
                    isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
                ) {
                    Button("好") {}
                } message: {
                    Text(model.alertMessage ?? "")
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
            }
        }
    }
}

/// 統計卡的一列：標題、金額、說明。
private struct SummaryRow: View {
    let title: String
    let amount: Money
    let detail: String
    var warnsWhenNegative = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(amount.formatted())
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(warnsWhenNegative && amount < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(amount.spokenText),\(detail)")
    }
}

private struct BankAccountRow: View {
    let account: BankAccount

    var body: some View {
        HStack(spacing: 12) {
            AccountColorMark(hex: account.colorHex)
            Text(account.name)
            Spacer()
            Text(account.balance.formatted())
                .monospacedDigit()
                .foregroundStyle(account.balance < .zero ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.name),餘額 \(account.balance.spokenText)")
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
