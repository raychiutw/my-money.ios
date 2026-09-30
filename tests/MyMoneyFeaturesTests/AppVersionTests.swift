import MyMoneyFeatures
import Testing

@Suite("「我的」的版本文字")
struct AppVersionTests {
    @Test("版號加 build 號:版本 0.1.0（36707214745）")
    func showsVersionAndBuild() {
        #expect(AppVersion(shortVersion: "0.1.0", build: "36707214745").text == "版本 0.1.0（36707214745）")
    }

    @Test("本機 Debug 建置的 build 是 1，照常顯示")
    func debugBuildIsOne() {
        #expect(AppVersion(shortVersion: "0.1.0", build: "1").text == "版本 0.1.0（1）")
    }

    @Test("從 Info.plist 的內容讀短版本與 build 號")
    func readsFromInfoDictionary() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "42", "CFBundleName": "MyMoney"]

        let version = AppVersion(infoDictionary: info)

        #expect(version == AppVersion(shortVersion: "0.2.0", build: "42"))
        #expect(version.text == "版本 0.2.0（42）")
    }

    @Test("沒有 build 號時不顯示括號")
    func omitsParenthesesWithoutBuild() {
        #expect(AppVersion(shortVersion: "0.1.0", build: "").text == "版本 0.1.0")
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "0.1.0"]).text == "版本 0.1.0")
    }

    @Test("讀不到版號時寫「未知」，不留下空白")
    func unknownWhenVersionIsMissing() {
        #expect(AppVersion(infoDictionary: nil).text == "版本 未知")
        #expect(AppVersion(infoDictionary: [:]).text == "版本 未知")
        #expect(AppVersion(shortVersion: " ", build: "7").text == "版本 未知（7）")
    }

    @Test("版號與 build 號前後的空白不算")
    func trimsWhitespace() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": " 0.1.0\n", "CFBundleVersion": " 9 "]).text == "版本 0.1.0（9）")
    }
}
