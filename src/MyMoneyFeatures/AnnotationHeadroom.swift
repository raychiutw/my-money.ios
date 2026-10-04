import SwiftUI

/// 長條圖最高那根的金額標註畫在圖的上緣外面(`overflowResolution` 的 y 設為 `.disabled`),圖的上方要留一個標註的高度,
/// 才不會壓到上面的內容(家庭頁「誰轉給誰」那行字 #157、記帳頁的「支出佔收入」比例條 #163)。
/// 高度跟標註同一個文字樣式(`footnote`)一起放大,所以字級放大時留的空間也跟著變大;兩張長條圖共用。
struct AnnotationHeadroom: ViewModifier {
    /// 預設字級的高度(pt):一行 `footnote` 加上標註與長條之間的空隙。
    static let baseHeight: CGFloat = 28

    @ScaledMetric(relativeTo: .footnote) private var headroom: CGFloat = AnnotationHeadroom.baseHeight

    func body(content: Content) -> some View {
        content.padding(.top, headroom)
    }
}

extension View {
    /// 圖的上方留標註的高度(見 `AnnotationHeadroom`)。
    func annotationHeadroom() -> some View {
        modifier(AnnotationHeadroom())
    }
}
