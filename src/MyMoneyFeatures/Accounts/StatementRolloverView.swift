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
            .interactiveDismissDisabled(model.isSaving)
            .inlineNavigationTitle()
            .toolbar {
                // 送出中不能關閉:關掉之後看不到結果，也看不到失敗的訊息。
                SheetCloseButton { if !model.isSaving { dismiss() } }
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
            // 只留會影響決定的狀態:結算的是哪一期、上期延入款預設已經納入。
            VStack(alignment: .leading, spacing: 4) {
                if let note = model.periodNote {
                    Text(note)
                        .accessibilityIdentifier("statementRollover.periodNote")
                }
                if let note = model.priorDeferredNote {
                    Text(note)
                }
            }
        }
    }

    /// 四層摘要(上游 ADR 0030):出帳淨額;刷卡與刷退;本期新增、本期延後、上期延入(本期新增 − 本期延後 + 上期延入 = 出帳淨額);
    /// 出帳後的待繳與剩餘未出帳。每一項附筆數。
    private func summarySection(_ outlook: StatementOutlook) -> some View {
        Group {
            Section {
                AmountRow(title: "本期出帳淨額(\(outlook.expenseCount + outlook.refundCount) 筆)", amount: .plain(outlook.net))
                    .accessibilityIdentifier("statementRollover.net")
                AmountRow(title: "刷卡金額(\(outlook.expenseCount) 筆)", amount: .plain(outlook.expense))
                AmountRow(title: "刷退折抵(\(outlook.refundCount) 筆)", amount: .inflow(outlook.refund))
            } header: {
                Text("出帳淨額")
            }
            Section {
                AmountRow(title: "本期新增(\(outlook.newInCycleCount) 筆)", amount: .plain(outlook.newInCycle))
                AmountRow(title: "本期延後(\(outlook.deferredCount) 筆)", amount: .plain(outlook.deferred))
                    .accessibilityIdentifier("statementRollover.deferred")
                AmountRow(title: "上期延入(\(outlook.priorIncomingCount) 筆)", amount: .plain(outlook.priorIncoming))
            } header: {
                Text("組成")
            }
            Section {
                AmountRow(title: "出帳後已出帳待繳款", amount: .plain(outlook.projectedBilled))
                    .accessibilityIdentifier("statementRollover.billed")
                AmountRow(title: "剩餘未出帳(\(outlook.remainingUnbilledCount) 筆)", amount: .plain(outlook.projectedUnbilled))
                    .accessibilityIdentifier("statementRollover.unbilled")
                if outlook.sharedDebt > .zero {
                    AmountRow(title: "其中家庭公帳代墊", amount: .plain(outlook.sharedDebt))
                    AmountRow(title: "其中個人私帳", amount: .plain(outlook.personalDebt))
                }
            } header: {
                Text("出帳後")
            }
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
            // 共用的明細卡(#289，DESIGN.md「明細卡與輸入框」第三版):標題用分類，備註在最下面一排,日期與狀態是膠囊。
            EntryCard(
                title: item.category.name, chips: [model.itemDayText(item), model.itemBadgeText(item)].compactMap { $0 },
                amount: item.kind == .expense ? .outflow(item.amount) : .inflow(item.amount),
                note: item.note.isEmpty ? nil : item.note, reservesMenuSpace: false
            )
            .strikethrough(isDeferred)
        }
        // 開關打開是 CI 填色(ADR-0009:CI 色一律以明確色票套用，不靠全域強調色)。
        .tint(Color.ciFill)
        // 開關的值維持系統的開／關:開 = 延至下期，所以把「延至下期」放進標籤。
        .accessibilityLabel("\(item.note.isEmpty ? item.category.name : item.note)，\(model.itemDetailText(item))，\(item.amount.spokenText)，\(Terms.deferredToNextStatement)")
        .accessibilityIdentifier("statementRollover.item.\(item.id.rawValue)")
    }
}
