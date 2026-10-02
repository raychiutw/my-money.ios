import MyMoneyDomain
import SwiftUI

/// 「我的」 → 機器人記帳：綁定驗證碼、已綁定的帳號、模擬對話、Webhook 網址(parity.md「機器人記帳」)。
/// 不顯示假的「已連線」狀態(parity 刻意偏離第 22 項);LINE／Telegram 的設定步驟不顯示(刻意偏離第 43 項)。
struct BotScreen: View {
    @Bindable var model: BotModel
    @State private var pendingUnbind: BotBinding?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
            pairingSection
            bindingsSection
            // 會寫入真的交易記錄的警告放在模擬對話畫面上方，這裡不重複。
            Section {
                NavigationLink("模擬對話") {
                    BotChatScreen(model: model)
                }
            }
            webhookSection
        }
        .skeletonTransition(value: model.isLoadingBindings)
        .navigationTitle("機器人記帳")
        .inlineNavigationTitle()
        .task { await model.load() }
        .confirmationDialog(
            "解除機器人綁定",
            isPresented: Binding(get: { pendingUnbind != nil }, set: { if !$0 { pendingUnbind = nil } }),
            titleVisibility: .visible,
            presenting: pendingUnbind
        ) { binding in
            Button("解除", role: .destructive) {
                Task { await model.unbind(binding) }
            }
            Button("取消", role: .cancel) {}
        } message: { binding in
            Text(model.unbindConfirmation(for: binding))
        }
        .alert(
            "無法完成",
            isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var pairingSection: some View {
        // 綁定驗證碼的效期看倒數，不另外寫說明;「傳送：綁定 綁定驗證碼」是完成流程必要的指示(DESIGN.md「說明文字」第 6 類)。
        Section("綁定 LINE 或 Telegram") {
            // 有沒有這一列在列的層級判斷：還沒產生時不能留下空白列(#79)。
            // 每秒重算剩下的時間;歸零時隱藏綁定驗證碼，改顯示已過期。
            if model.hasPairingCode {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let code = model.visiblePairingCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(code)
                                .font(.largeTitle.monospaced().bold())
                                .textSelection(.enabled)
                                .accessibilityIdentifier("bot.pairingCode")
                            Text("剩下 \(model.countdownText)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text("在 LINE 或 Telegram 的聊天室傳送：\(model.pairingCommand)")
                                .font(.subheadline)
                            CopyButton(title: "複製指令", copiedTitle: "已複製指令", text: model.pairingCommand)
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("bot.copyCommand")
                        }
                    } else {
                        Text("綁定驗證碼已過期")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("產生綁定驗證碼") {
                Task { await model.generatePairingCode() }
            }
            .accessibilityIdentifier("bot.generate")
        }
    }

    private var bindingsSection: some View {
        Section("已綁定的帳號") {
            if model.isLoadingBindings {
                // 資料回來之前不顯示「尚未綁定」,改顯示兩列骨架(DESIGN.md「載入狀態」)。
                SkeletonItemRow()
                    .skeletonAnnouncement()
                SkeletonItemRow()
                    .skeletonRow()
            } else if let message = model.bindingsErrorMessage, model.bindings == nil {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("重試") {
                    Task { await model.load() }
                }
            }
            if model.bindings?.isEmpty == true {
                Text("尚未綁定任何 LINE 或 Telegram 帳號")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.bindings ?? []) { binding in
                LabeledContent(binding.platform.title, value: binding.displayName ?? "")
                    .swipeActions {
                        Button("解除", systemImage: "xmark.circle", role: .destructive) {
                            pendingUnbind = binding
                        }
                    }
                    .contextMenu {
                        Button("解除", systemImage: "xmark.circle", role: .destructive) {
                            pendingUnbind = binding
                        }
                    }
            }
        }
    }

    /// 只留 Webhook 網址和「複製」;LINE／Telegram 的設定步驟不顯示(parity 刻意偏離第 43 項)。
    private var webhookSection: some View {
        Section("Webhook 網址") {
            webhookRow(.line, url: BotModel.lineWebhook)
            webhookRow(.telegram, url: BotModel.telegramWebhook)
        }
    }

    /// 網址單行、從中間截斷，看得到網域和結尾的平台(#79);要完整的網址就按「複製」(只有圖示，VoiceOver 念「複製」)。
    /// 無障礙字級時單行只放得下十幾個字、看不到網域(AX5 截圖):改成不截斷、完整折行，「複製」放到網址下面。
    private func webhookRow(_ platform: BotPlatform, url: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(platform.title)
                Text(url)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CopyButton(text: url)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("bot.copyWebhook.\(platform.rawValue)")
        }
        // 分隔線從文字的起點開始，不是從「複製」開始。
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

/// 模擬對話：歡迎訊息、4 個快捷範例、每則訊息附時間，等待回覆時顯示「思考中」。
struct BotChatScreen: View {
    @Bindable var model: BotModel

    var body: some View {
        VStack(spacing: 0) {
            Label("這裡送出的訊息會寫入真的交易記錄。", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.orange.opacity(0.1))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if model.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("思考中…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages.count) {
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(BotModel.examples, id: \.self) { example in
                        Button(example) {
                            model.draft = example
                            Task { await model.send() }
                        }
                        .buttonStyle(.glass)
                        .disabled(model.isThinking)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                TextField("例如：午餐 120、高鐵 1490 信用卡、查帳", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.send() } }
                    .accessibilityIdentifier("bot.draft")
                Button("送出", systemImage: "paperplane.fill") {
                    Task { await model.send() }
                }
                .labelStyle(.iconOnly)
                .disabled(model.isThinking || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("bot.send")
            }
            .padding()
        }
        .navigationTitle("模擬對話")
        .inlineNavigationTitle()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
            Text(message.text)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(background)
                )
            Text(message.time.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
        // 誰說的只靠左右位置和顏色看得出來，VoiceOver 要念出來。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(message.sender == .user ? "我" : "記帳小幫手")\(message.isError ? ",錯誤" : ""):\(message.text),"
                + message.time.formatted(date: .omitted, time: .shortened)
        )
    }

    /// 我的訊息用淡色的 tint 底配主要文字色(單色，DESIGN.md「顏色」)。
    private var background: AnyShapeStyle {
        if message.isError { return AnyShapeStyle(.red.opacity(0.15)) }
        return message.sender == .user ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary)
    }
}
