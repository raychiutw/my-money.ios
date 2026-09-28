import MyMoneyDomain
import SwiftUI

/// 帳號 sheet → 機器人記帳：綁定驗證碼、已綁定的帳號、模擬對話、webhook 設定說明(parity.md「機器人記帳」)。
/// 不顯示假的「已連線」狀態(parity 刻意偏離第 22 項)。
struct BotScreen: View {
    @Bindable var model: BotModel
    @State private var pendingUnbind: BotBinding?
    @Environment(\.copiedFeedbackDuration) private var copiedFeedbackDuration
    @State private var isCopied = false

    var body: some View {
        List {
            pairingSection
            bindingsSection
            Section {
                NavigationLink("模擬對話") {
                    BotChatScreen(model: model)
                }
            } footer: {
                Text("在 app 裡試用機器人記帳。這裡送出的訊息會寫入真的交易紀錄。")
            }
            webhookSection
        }
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
        Section {
            // 每秒重算剩下的時間;歸零時隱藏綁定驗證碼。
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
                        Button(isCopied ? "已複製指令" : "複製指令", systemImage: isCopied ? "checkmark" : "doc.on.doc") {
                            copyToPasteboard(model.pairingCommand)
                            isCopied = true
                            Task {
                                try? await Task.sleep(for: copiedFeedbackDuration)
                                isCopied = false
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("bot.copyCommand")
                    }
                }
            }
            Button("產生綁定驗證碼") {
                Task { await model.generatePairingCode() }
            }
            .accessibilityIdentifier("bot.generate")
        } header: {
            Text("綁定 LINE 或 Telegram")
        } footer: {
            // web 寫「6 位數」,實際是英數混合(parity 刻意偏離第 14 項)。
            Text("綁定驗證碼是 6 碼大寫英文字母與數字，10 分鐘內有效。重新產生後，舊的就不能用。")
        }
    }

    private var bindingsSection: some View {
        Section("已綁定的帳號") {
            if model.bindings == nil {
                // 資料回來之前不顯示「尚未綁定」(DESIGN.md「載入」)。
                ProgressView()
                    .frame(maxWidth: .infinity)
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

    private var webhookSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("LINE Messaging API")
                    .font(.subheadline.bold())
                Text("1. 在 LINE Developers Console 建立 Messaging API Channel。")
                Text("2. 在 Messaging API 設定填入 Webhook URL:")
                Text(BotModel.lineWebhook)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                Text("3. 打開「Use Webhook」。")
                Text("4. 在 Workers 設定 LINE_CHANNEL_SECRET 與 LINE_CHANNEL_ACCESS_TOKEN。")
                Text("5. 加機器人好友，傳送「綁定 綁定驗證碼」。")
            }
            .font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Telegram Bot")
                    .font(.subheadline.bold())
                Text("1. 在 Telegram 找 @BotFather,輸入 /newbot 建立機器人。")
                Text("2. 在 Workers 設定 TELEGRAM_BOT_TOKEN。")
                Text("3. 呼叫 Telegram 的 setWebhook,網址是:")
                Text(BotModel.telegramWebhook)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
                Text("4. 私訊機器人，傳送「綁定 綁定驗證碼」。")
            }
            .font(.subheadline)
        } header: {
            Text("Webhook 設定說明")
        }
    }
}

/// 模擬對話：歡迎訊息、4 個快捷範例、每則訊息附時間，等待回覆時顯示「思考中」。
struct BotChatScreen: View {
    @Bindable var model: BotModel

    var body: some View {
        VStack(spacing: 0) {
            Label("這裡送出的訊息會寫入真的交易紀錄。", systemImage: "exclamationmark.triangle.fill")
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
                        .buttonStyle(.bordered)
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

    /// 我的訊息用淡色的 tint 底配主要文字色：白字配品牌粉在深色模式只有 2.27:1(DESIGN.md「顏色」)。
    private var background: AnyShapeStyle {
        if message.isError { return AnyShapeStyle(.red.opacity(0.15)) }
        return message.sender == .user ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary)
    }
}
