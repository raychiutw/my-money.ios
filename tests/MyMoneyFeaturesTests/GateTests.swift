import MyMoneyTestSupport
import Testing

/// 測試輔助 `Gate`(#208 第 4 項):取消一個等待者只放行那一個,不放行別的等待者。
/// (以前取消任何一個都會放行全部:UI 測試切 tab 取消總覽的請求,帳戶頁停住的請求也被放行,骨架屏提早消失。)
@Suite("Gate:取消只放行被取消的那一個等待者")
struct GateTests {
    @Test("取消 A 之後,B 仍然停著,直到 open", .timeLimit(.minutes(1)))
    func cancellingOneWaiterKeepsOthersWaiting() async {
        let gate = Gate()
        let flags = Flags()
        let a = Task { await gate.pass(); await flags.set("a") }
        let b = Task { await gate.pass(); await flags.set("b") }
        await gate.waitUntilReached()
        // 讓兩個等待者都登記進去。
        try? await Task.sleep(for: .milliseconds(100))

        a.cancel()
        await a.value
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await flags.values == ["a"], "只有被取消的 A 該被放行;B 還停著")
        await gate.open()
        await b.value
        #expect(await flags.values == ["a", "b"])
    }

    @Test("open 放行全部等待者,之後的 pass 不再停", .timeLimit(.minutes(1)))
    func openReleasesEveryone() async {
        let gate = Gate()
        let waiter = Task { await gate.pass() }
        await gate.waitUntilReached()
        await gate.open()
        await waiter.value
        await gate.pass()
    }
}

private actor Flags {
    private(set) var values: [String] = []
    func set(_ value: String) { values.append(value) }
}
