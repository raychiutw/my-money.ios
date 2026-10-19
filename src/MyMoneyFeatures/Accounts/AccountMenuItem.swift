import MyMoneyDomain

/// 帳戶列與詳細頁 toolbar 的 ⋯ 選單項目。項目與順序由 model 決定(列、詳細頁共用),畫面只負責畫出來;
/// 沒有權限或用不到的項目直接不給(HIG Context menus:隱藏、不要變灰),破壞性的刪除放最後。
public enum AccountMenuItem: Hashable, Sendable {
    case transfer
    case pay(CardPaymentModel.Preset)
    case rollover
    case reconcile
    case edit
    case delete

    /// 現金與活存帳戶:轉帳不受修改權限限制;編輯、刪除需要修改權限。信用卡沒有轉帳。
    static func items(
        for account: Account, canModify: Bool, canOperate: Bool, paymentPresets: [CardPaymentModel.Preset], showsRollover: Bool
    ) -> [AccountMenuItem] {
        var items: [AccountMenuItem] = []
        switch account {
        case .cash, .bank:
            items.append(.transfer)
        case .creditCard:
            items += paymentPresets.map(AccountMenuItem.pay)
            if showsRollover { items.append(.rollover) }
            if canOperate { items.append(.reconcile) }
        }
        if canModify { items += [.edit, .delete] }
        return items
    }
}
