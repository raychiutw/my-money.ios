import MyMoneyDomain
import SwiftUI

/// 新增或編輯資產帳戶的 sheet(DESIGN.md「元件對照」:Form + 取消 / 儲存)。
struct AccountEditorView: View {
    @Bindable var model: AccountEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case amount
        case unbilled
        case creditLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                // 新增時可以切換類型:3 個選項用內嵌選擇列，點一下就選，選項字不會像分段控制一樣被壓小(#65、ADR-0004、#90)。
                if model.canChangeKind {
                    Section("類型") {
                        Picker("類型", selection: $model.kind) {
                            Text("現金錢包").tag(AccountKind.cash)
                            Text("銀行存款帳戶").tag(AccountKind.bank)
                            Text("信用卡").tag(AccountKind.creditCard)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    // 欄位要有看得見的標籤，placeholder 只放範例(DESIGN.md「列與欄位」第 8 條，#78)。
                    LabeledContent("名稱") {
                        TextField("名稱", text: $model.name, prompt: Text(namePrompt))
                            .focused($focusedField, equals: .name)
                            .accessibilityIdentifier("accountEditor.name")
                    }
                    if model.showsAmountField {
                        amountRow(model.amountLabel, text: $model.amountText, field: .amount, identifier: "accountEditor.amount")
                    }
                }

                // 所有類型都能設歸屬，選項都是個人私帳、家庭共同基金(web 的「帳戶屬性歸屬」);預設個人私帳。
                Section("歸屬") {
                    Picker("歸屬", selection: $model.isJointFund) {
                        ForEach(model.ownershipChoices, id: \.isJointFund) { choice in
                            Text(choice.title).tag(choice.isJointFund)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if model.kind == .creditCard {
                    Section("信用卡") {
                        amountRow(model.unbilledLabel, text: $model.unbilledText, field: .unbilled, identifier: "accountEditor.unbilled")
                        amountRow("信用額度(選填)", text: $model.creditLimitText, field: .creditLimit, identifier: "accountEditor.creditLimit", prompt: nil)
                        dayPicker("結帳日", selection: $model.statementDay)
                        dayPicker("繳款日", selection: $model.paymentDueDay)
                    }
                }

                Section("代表色") {
                    ColorChoices(selection: $model.colorHex)
                }

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("accountEditor.error")
                    }
                }
            }
            .navigationTitle(model.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            if await model.save() { dismiss() }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("accountEditor.save")
                }
            }
            .keyboardDismissal(clearing: $focusedField)
            .onChange(of: model.errorMessage) { _, message in
                if let message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }
    }

    private var namePrompt: String {
        switch model.kind {
        case .cash: "例如：我的皮夾、客廳零用金盒"
        case .bank: "例如：薪轉戶"
        case .creditCard: "例如：旅遊卡"
        }
    }

    /// `prompt` 是留空時代表的值(存成 0 的欄位才顯示「0」)。
    private func amountRow(
        _ label: String, text: Binding<String>, field: Field, identifier: String, prompt: String? = "0"
    ) -> some View {
        LabeledContent(label) {
            AmountField(
                label, text: text, prompt: prompt.map { Text(verbatim: $0) },
                focus: $focusedField, equals: field, identifier: identifier
            )
        }
    }

    private func dayPicker(_ label: String, selection: Binding<Int?>) -> some View {
        Picker(label, selection: selection) {
            Text("未設定").tag(Int?.none)
            ForEach(1...31, id: \.self) { day in
                Text("每月 \(day) 號").tag(Int?.some(day))
            }
        }
    }
}

/// 8 種代表色的圓形按鈕(#71)。一行放得下就排一行;放不下(例如 iPhone 直向)就可以左右滑，
/// 邊緣露出半顆色塊，提示還能滑，打開時捲到已選的顏色。每顆的觸控範圍至少 44 pt,
/// VoiceOver 念顏色的名稱，選中的標記為已選取。維持 web 的 8 色，不用系統的 `ColorPicker`(ADR-0001)。
private struct ColorChoices: View {
    @Binding var selection: String
    /// 可以滑的時候，捲動位置對準的色塊。出現時設成已選的顏色，捲到它(編輯既有帳戶時也一樣)。
    @State private var scrolledHex: String?

    /// 觸控範圍的最小邊長(DESIGN.md「無障礙」)。
    private static let minimumTarget: CGFloat = 44
    /// 可以滑的時候一次看得到幾顆：多出的半顆露在邊緣，提示還能滑。
    private static let visibleCount: CGFloat = 6.5
    /// 排一行時左右至少留的空白，跟表單列預設的內容邊距差不多。
    private static let rowPadding: CGFloat = 16
    /// 可以滑的時候，捲到兩端時留的空白。iPhone 17 直向的色塊寬約 56 pt,第一顆的圓形因此大致跟表單列的文字對齊。
    private static let scrollMargin: CGFloat = 4

    var body: some View {
        // 用實際寬度判斷：放得下一行就排一行，放不下改成可以左右滑。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(AccountColors.all, id: \.hex) { color in
                    swatch(color)
                        .frame(width: Self.minimumTarget)
                }
            }
            .padding(.horizontal, Self.rowPadding)
            .frame(maxWidth: .infinity)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(AccountColors.all, id: \.hex) { color in
                        swatch(color)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                max(Self.minimumTarget, length / Self.visibleCount)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Self.scrollMargin, for: .scrollContent)
            .scrollIndicators(.hidden)
            // 停下來時對齊色塊的邊界，右緣(捲到底時是左緣)一定露出半顆。
            // 捲到已選的顏色也用前緣對齊;置中的話，中間的顏色兩端剛好都是完整的圓，看不出還能滑。
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledHex, anchor: .leading)
            // 一開始就給值不會捲動，要在出現後才設。
            .onAppear { scrolledHex = selection }
        }
        // 捲動範圍延伸到表單列的兩端，色塊從列的邊緣露出來，不會在列裡面被裁掉。
        .listRowInsets(.horizontal, 0)
    }

    private func swatch(_ color: (hex: String, name: String)) -> some View {
        Button {
            selection = color.hex
        } label: {
            Circle()
                .fill(Color(hex: color.hex) ?? .gray)
                .overlay {
                    if selection == color.hex {
                        // 圓固定 32pt,打勾的字級設上限，大字級時才不會超出圓(#78,AX5 截圖)。
                        Image(systemName: "checkmark")
                            .font(.footnote.bold())
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }
                .frame(width: 32, height: 32)
                .frame(maxWidth: .infinity, minHeight: Self.minimumTarget)
                // 圓形外面、觸控範圍裡的空白也點得到。
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selection == color.hex ? .isSelected : [])
    }
}
