import SwiftUI

/// 破壞性的滑動動作(刪除、移除、解除;#204):**紅色**底加圖示與文字。
///
/// app 的強調色淺色是黑、深色是白,滑動動作會用它當底色,destructive 的紅色被蓋掉
/// (截圖:淺色是黑色圓鈕、深色是白底白圖示,看不見垃圾桶)。所以明確指定紅色。全 app 的破壞性滑動動作都用這個,新畫面不要自己寫 `.tint`。
struct DestructiveSwipeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String = "刪除", systemImage: String = "trash", action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage, role: .destructive, action: action)
            .tint(.red)
    }
}

/// 非破壞性的滑動動作(編輯、轉帳):中性灰底(#134:強調色在深色模式是白色,白底白字)。
struct NeutralSwipeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .tint(.gray)
    }
}
