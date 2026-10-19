import SwiftUI

/// ⋯ 選單裡的按鈕:帳戶列(`MoreMenu`)與詳細頁 toolbar 共用。項目由 model 的 `menuItems` 決定,刪除用系統紅(破壞性、放最後)。
struct AccountMenuButtons: View {
    let items: [AccountMenuItem]
    /// 校準進行中:停用「校準未出帳」。
    var isReconciling = false
    let perform: (AccountMenuItem) -> Void

    var body: some View {
        ForEach(items, id: \.self) { item in
            Button(item.title(isReconciling: isReconciling), systemImage: item.systemImage, role: item == .delete ? .destructive : nil) {
                perform(item)
            }
            .disabled(item == .reconcile && isReconciling)
        }
    }
}

extension AccountMenuItem {
    func title(isReconciling: Bool = false) -> String {
        switch self {
        case .transfer: "轉帳"
        case .pay(let preset): preset.title
        case .rollover: "出帳作業"
        case .reconcile: isReconciling ? "校準中…" : "校準未出帳"
        case .edit: "編輯"
        case .delete: "刪除"
        }
    }

    var systemImage: String {
        switch self {
        case .transfer: "arrow.left.arrow.right"
        case .pay(let preset): preset.systemImage
        case .rollover: "calendar.badge.clock"
        case .reconcile: "arrow.triangle.2.circlepath"
        case .edit: "pencil"
        case .delete: "trash"
        }
    }
}
