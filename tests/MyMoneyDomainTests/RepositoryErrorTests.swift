import Foundation
import MyMoneyDomain
import Testing

@Suite("repository 錯誤給人看的訊息")
struct RepositoryErrorTests {
    @Test("後端拒絕時原樣顯示後端的訊息")
    func rejectedShowsBackendMessage() {
        #expect(RepositoryError.rejected("Email 或密碼錯誤").localizedDescription == "Email 或密碼錯誤")
    }

    @Test("無法解析的回應顯示「伺服器無回應」")
    func unreadableResponseShowsNoResponse() {
        #expect(RepositoryError.unreadableResponse.localizedDescription == "伺服器無回應")
    }
}
