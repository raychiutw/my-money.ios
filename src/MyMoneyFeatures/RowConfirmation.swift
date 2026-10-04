import SwiftUI

extension View {
    /// 確認訊息掛在**觸發它的那一列**(或按鈕)上(#169)。
    ///
    /// iOS 26 在 iPhone 上把 `confirmationDialog` 畫成泡泡(popover),箭頭指向掛這個 modifier 的 view。
    /// 掛在整個畫面(清單)上,泡泡就出現在不相關的地方(例如家庭頁下方的「離開家庭」,泡泡卻指著上面的「查看代墊明細」);
    /// 掛在觸發的那一列上,箭頭才指著使用者剛剛滑開或長按的那一列。
    /// `pending` 是畫面上「等待確認的項目」,只有 id 相同的那一列顯示泡泡。
    func rowConfirmationDialog<Item: Identifiable, Actions: View, Message: View>(
        _ title: String,
        pending: Binding<Item?>,
        for item: Item,
        @ViewBuilder actions: @escaping (Item) -> Actions,
        @ViewBuilder message: @escaping (Item) -> Message
    ) -> some View {
        let isPending = pending.wrappedValue?.id == item.id
        return confirmationDialog(
            title,
            isPresented: Binding(
                get: { isPending },
                set: { presented in
                    if !presented, pending.wrappedValue?.id == item.id { pending.wrappedValue = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: isPending ? item : nil,
            actions: actions,
            message: message
        )
    }
}
