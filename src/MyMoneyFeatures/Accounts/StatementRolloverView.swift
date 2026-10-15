import MyMoneyDomain
import SwiftUI

/// 結帳日出帳作業的預覽 sheet(DESIGN.md「元件對照」:Form + 取消 / 確認)。切換明細的「延至下期」只在本地試算，
/// 按「確認」才送出;成功時把後端的訊息交給 `onDone`。
struct StatementRolloverView: View {
    let model: StatementRolloverModel
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let outlook = model.outlook {
                    periodSection
                    summarySection(outlook)
                    if model.isEmptyCycle {
                        Section {
                            Text("這一期沒有刷卡記錄")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("statementRollover.empty")
                        }
                    } else {
                        itemsSection
                    }
                } else if model.errorMessage == nil {
                    Section {
                        ProgressView("載入中…")
                            .frame(maxWidth: .infinity)
                    }
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("statementRollover.error")
                        if model.preview == nil {
                            Button("重試") { Task { await model.load() } }
                                .accessibilityIdentifier("statementRollover.retry")
                        }
                    }
                }
            }
            .navigationTitle("出帳作業")
            .inlineNavigationTitle()
            .toolbar {
                SheetCloseButton { dismiss() }
                SheetConfirmButton("確認", isDisabled: !model.canConfirm, identifier: "statementRollover.submit") {
                    Task {
                        if let message = await model.submit() {
                            dismiss()
                            onDone(message)
                        }
                    }
                }
            }
            .task { await model.load() }
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private var periodSection: some View {
        Section {
            LabeledContent("信用卡") { Text(model.card.name) }
            if let period = model.periodText {
                LabeledContent("結算區間") { Text(period) }
                    .accessibilityIdentifier("statementRollover.period")
            }
        } footer: {
            // 只留會影響決定的狀態:上期延入款預設已經納入。
            if let note = model.priorDeferredNote {
                Text(note)
            }
        }
    }

    private func summarySection(_ outlook: StatementOutlook) -> some View {
        Section {
            AmountRow(title: "本期消費(\(outlook.expenseCount) 筆)", amount: .plain(outlook.expense))
            if outlook.refund > .zero {
                AmountRow(title: "刷退折抵(\(outlook.refundCount) 筆)", amount: .inflow(outlook.refund))
            }
            AmountRow(title: "出帳淨額", amount: .plain(outlook.net))
                .accessibilityIdentifier("statementRollover.net")
            if outlook.sharedDebt > .zero {
                AmountRow(title: "其中家庭公帳代墊", amount: .plain(outlook.sharedDebt))
                AmountRow(title: "其中個人私帳", amount: .plain(outlook.personalDebt))
            }
            AmountRow(title: "出帳後已出帳待繳款", amount: .plain(outlook.projectedBilled))
                .accessibilityIdentifier("statementRollover.billed")
            AmountRow(title: "出帳後未出帳款", amount: .plain(outlook.projectedUnbilled))
                .accessibilityIdentifier("statementRollover.unbilled")
        } header: {
            Text("出帳後")
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(model.items) { item in
                itemRow(item)
            }
        } header: {
            // 欄位標題:右邊的開關是「延至下期」。
            HStack {
                Text("明細(\(model.items.count) 筆)")
                Spacer()
                Text(Terms.deferredToNextStatement)
            }
        }
    }

    /// 一筆明細:開關打開是延至下期(金額加刪除線，不算進本期)。
    private func itemRow(_ item: StatementItem) -> some View {
        let isDeferred = model.isDeferred(item.id)
        return Toggle(isOn: Binding(get: { isDeferred }, set: { _ in model.toggleDeferral(item.id) })) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.note.isEmpty ? item.category.name : "\(item.category.name) · \(item.note)")
                    Text(model.itemDetailText(item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                AmountText(item.kind == .expense ? .outflow(item.amount) : .inflow(item.amount))
                    .monospacedDigit()
            }
            .strikethrough(isDeferred)
        }
        // 開關打開是 CI 填色(ADR-0009:CI 色一律以明確色票套用，不靠全域強調色)。
        .tint(Color.ciFill)
        // 開關的值維持系統的開／關:開 = 延至下期，所以把「延至下期」放進標籤。
        .accessibilityLabel("\(item.note.isEmpty ? item.category.name : item.note)，\(model.itemDetailText(item))，\(item.amount.spokenText)，\(Terms.deferredToNextStatement)")
        .accessibilityIdentifier("statementRollover.item.\(item.id.rawValue)")
    }
}
