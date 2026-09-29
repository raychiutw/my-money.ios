import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 可以手動往前撥的時鐘。
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("機器人記帳")
struct BotTests {
    private let clock = TestClock()
    private let dataVersion = DataVersion()

    private func model(_ repository: InMemoryBotRepository = .sample()) -> BotModel {
        BotModel(repository: repository, dataVersion: dataVersion, now: { [clock] in clock.now })
    }

    @Test("綁定驗證碼每秒倒數「M 分 S 秒」,歸零時隱藏")
    func pairingCountdown() async {
        let model = model()

        await model.generatePairingCode()
        #expect(model.visiblePairingCode == "AB12CD")
        #expect(model.countdownText == "10 分 0 秒")

        clock.advance(61)
        #expect(model.countdownText == "8 分 59 秒")
        #expect(model.visiblePairingCode == "AB12CD")

        clock.advance(539)
        #expect(model.visiblePairingCode == nil)
    }

    @Test("「複製指令」複製的內容是「綁定 {綁定驗證碼}」")
    func copyCommand() async {
        let model = model()

        await model.generatePairingCode()

        #expect(model.pairingCommand == "綁定 AB12CD")
    }

    @Test("已綁定的帳號載入之前是 nil,畫面不會先顯示「尚未綁定」")
    func bindingsBeforeLoading() async {
        let model = model()
        #expect(model.bindings == nil)
        #expect(model.isLoadingBindings)

        await model.load()
        #expect(model.bindings?.count == 1)
        #expect(!model.isLoadingBindings)
    }

    @Test("已綁定的帳號載入失敗時不再停在骨架屏，顯示失敗原因;重試成功後清掉")
    func bindingsLoadFailure() async {
        let repository = InMemoryBotRepository.sample()
        await repository.fail(with: .rejected("伺服器無回應"))
        let model = model(repository)

        await model.load()
        #expect(!model.isLoadingBindings)
        #expect(model.bindingsErrorMessage == "伺服器無回應")

        await repository.fail(with: nil)
        await model.load()
        #expect(model.bindingsErrorMessage == nil)
        #expect(model.bindings?.count == 1)
    }

    /// 後端第一次模擬對話時會建立「模擬測試助手」的綁定(parity 後端造成的第 16 項)。
    @Test("模擬對話送出後重抓已綁定的帳號")
    func sendReloadsBindings() async {
        let model = model()
        await model.load()
        model.draft = "午餐 120"

        await model.send()

        #expect(model.bindings?.map(\.displayName) == ["小明的 LINE", "模擬測試助手"])
    }

    @Test("已綁定的帳號;解除前確認，解除後重抓")
    func unbind() async throws {
        let repository = InMemoryBotRepository.sample()
        let model = model(repository)
        await model.load()
        let binding = try #require(model.bindings?.first)

        #expect(model.unbindConfirmation(for: binding) == "確定要解除 LINE「小明的 LINE」的機器人綁定嗎？")
        await model.unbind(binding)

        #expect(await repository.unboundIDs == [binding.id])
        #expect(model.bindings?.isEmpty == true)
    }

    @Test("模擬對話的開頭是歡迎訊息，提供 4 個快捷範例")
    func welcome() {
        let model = model()

        #expect(model.messages.count == 1)
        #expect(model.messages.first?.sender == .bot)
        #expect(BotModel.examples == ["午餐 120", "一蘭拉麵 320 現金", "薪水 65000 銀行", "查帳"])
    }

    @Test("送出後附上機器人的回覆，清掉輸入框，資料版本遞增(寫入的是真的交易記錄)")
    func send() async throws {
        let repository = InMemoryBotRepository.sample()
        let model = model(repository)
        model.draft = " 午餐 120 "

        await model.send()

        #expect(await repository.simulatedTexts == ["午餐 120"])
        try #require(model.messages.count == 3)
        #expect(model.messages.map(\.sender) == [.bot, .user, .bot])
        #expect(model.messages[1].text == "午餐 120")
        #expect(model.messages[2].text == "記帳成功：午餐 120")
        #expect(model.messages[1].time == clock.now)
        #expect(model.draft.isEmpty)
        #expect(dataVersion.value == 1)
    }

    @Test("等待回覆時顯示「思考中」", .timeLimit(.minutes(1)))
    func thinking() async {
        let gate = Gate()
        let model = model(InMemoryBotRepository.sample(gate: gate))
        model.draft = "查帳"

        let sending = Task { await model.send() }
        await gate.waitUntilReached()
        #expect(model.isThinking)

        await gate.open()
        await sending.value
        #expect(!model.isThinking)
    }

    @Test("錯誤以一則訊息泡泡呈現")
    func errorBubble() async {
        let repository = InMemoryBotRepository.sample()
        await repository.fail(with: .rejected("請輸入測試訊息"))
        let model = model(repository)
        model.draft = "午餐 120"

        await model.send()

        #expect(model.messages.last?.text == "錯誤：請輸入測試訊息")
        #expect(model.messages.last?.isError == true)
        #expect(dataVersion.value == 0)
    }

    @Test("空白的訊息不送出")
    func emptyDraft() async {
        let repository = InMemoryBotRepository.sample()
        let model = model(repository)
        model.draft = "   "

        await model.send()

        #expect(await repository.simulatedTexts.isEmpty)
        #expect(model.messages.count == 1)
    }

    /// web 的網址多了 /api,網域也不對(parity 刻意偏離第 8 項)。
    @Test("Webhook 說明的網址")
    func webhookURLs() {
        #expect(BotModel.lineWebhook == "https://my-money-api.onion523.workers.dev/bot/webhook/line")
        #expect(BotModel.telegramWebhook == "https://my-money-api.onion523.workers.dev/bot/webhook/telegram")
    }
}
