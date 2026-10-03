import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 分段控制(支出｜收入、視角、設定｜規劃、週期類型):**字用 `subheadline` 文字樣式，即時跟著系統字級放大縮小**(#156)。
///
/// 系統的 `UISegmentedControl` 預設字是固定的 13pt、不跟 Dynamic Type 走(實測:最小到最大字級字高都一樣),
/// 以前用啟動時設定的 appearance 補救，但只取一次大小、上限 21pt，執行中改字級要重開 app。
/// 這裡自己用 `UIFontMetrics` 設字型，並在系統字級改變時重設，所以不用重開、也沒有上限。
/// 分段控制的高度是固定的，字級大到放不下(無障礙字級)就換成選單(`Picker(.menu)`)，字才不會被裁掉(#78 的 AX5 截圖)。
struct SegmentedPicker<Value: Hashable>: View {
    /// VoiceOver 念的標籤(畫面上不顯示)。
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var identifier: String?
    /// 撐滿可用寬度(列表裡的整列);否則依內容的寬度(導覽列中間)。
    var fillsWidth = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: String, options: [(value: Value, title: String)], selection: Binding<Value>, identifier: String? = nil,
        fillsWidth: Bool = false
    ) {
        self.title = title
        self.options = options
        _selection = selection
        self.identifier = identifier
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize {
            menu
        } else {
            ScalingSegmentedControl(
                title: title, options: options, selection: $selection, identifier: identifier, fillsWidth: fillsWidth,
                dynamicTypeSize: dynamicTypeSize
            )
        }
        #else
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identifier ?? "")
        #endif
    }

    /// 無障礙字級:選單，label 是目前的選擇，字照系統大小、折行不裁切。
    private var menu: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier ?? "")
    }
}

#if os(iOS)
private struct ScalingSegmentedControl<Value: Hashable>: UIViewRepresentable {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    let identifier: String?
    let fillsWidth: Bool
    /// SwiftUI 環境的字級:只當作「字級改變了」的觸發——改變時 SwiftUI 會重跑 `updateUIView`。實際的大小看控制項自己的
    /// trait(導覽列裡的項目系統會限制字級範圍，環境值跟控制項實際的字級不一定一樣)。
    let dynamicTypeSize: DynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        // 系統字級改變時重設字型(不用重開 app)。
        control.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (control: UISegmentedControl, _) in
            Self.applyFonts(to: control)
        }
        control.accessibilityIdentifier = identifier
        control.accessibilityLabel = title
        Self.applyFonts(to: control)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        Self.applyFonts(to: control)
        let titles = options.map(\.title)
        let current = (0..<control.numberOfSegments).map { control.titleForSegment(at: $0) }
        if current != titles {
            control.removeAllSegments()
            for (index, title) in titles.enumerated() {
                control.insertSegment(withTitle: title, at: index, animated: false)
            }
            control.invalidateIntrinsicContentSize()
        }
        control.selectedSegmentIndex = options.firstIndex { $0.value == selection } ?? UISegmentedControl.noSegment
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView control: UISegmentedControl, context: Context) -> CGSize? {
        let intrinsic = control.intrinsicContentSize
        let width = fillsWidth ? (proposal.width ?? intrinsic.width) : min(intrinsic.width, proposal.width ?? intrinsic.width)
        return CGSize(width: width, height: intrinsic.height)
    }

    /// `subheadline` 的預設大小 15pt(HIG 字級表，預設 Large)，經 `UIFontMetrics` 跟著系統字級縮放;選取的字加粗。
    static func applyFonts(to control: UISegmentedControl) {
        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        let traits = control.traitCollection
        let normal = metrics.scaledFont(for: .systemFont(ofSize: 15), compatibleWith: traits)
        let selected = metrics.scaledFont(for: .systemFont(ofSize: 15, weight: .semibold), compatibleWith: traits)
        control.setTitleTextAttributes([.font: normal], for: .normal)
        control.setTitleTextAttributes([.font: selected], for: .selected)
        control.invalidateIntrinsicContentSize()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScalingSegmentedControl

        init(_ parent: ScalingSegmentedControl) {
            self.parent = parent
        }

        @objc func valueChanged(_ control: UISegmentedControl) {
            let index = control.selectedSegmentIndex
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}
#endif
