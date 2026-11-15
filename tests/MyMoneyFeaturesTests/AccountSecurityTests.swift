import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("帳號安全:登入裝置與修改密碼(#338)")
struct AccountSecurityTests {
    private let thisPhone = InMemoryAccountSecurityRepository.thisPhone
    private let webBrowser = InMemoryAccountSecurityRepository.webBrowser

    @Test("登入工作階段載入前是 nil(顯示骨架),載入後照後端順序列出,標出這台裝置")
    func loadLoginSessions() async {
        let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository.sample())
        #expect(model.loginSessions == nil)
        #expect(model.isLoadingSessions)

        await model.load()

        #expect(model.loginSessions == [webBrowser, thisPhone])
        #expect(model.loginSessions?.filter(\.isCurrent) == [thisPhone])
        #expect(model.hasOtherSessions)
        #expect(!model.isLoadingSessions)
    }

    @Test("登入工作階段載入失敗時顯示原因,不停在骨架")
    func loadFailure() async {
        let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository(
            sessions: [], failure: .rejected("伺服器忙碌")
        ))

        await model.load()

        #expect(model.sessionsErrorMessage == "伺服器忙碌")
        #expect(!model.isLoadingSessions)
    }

    @Test("登出單一裝置後重新載入,清單不再有那台")
    func signOutOneSession() async {
        let repository = InMemoryAccountSecurityRepository.sample()
        let model = AccountSecurityModel(repository: repository)
        await model.load()

        await model.signOut(webBrowser)

        #expect(await repository.signedOutIDs == [webBrowser.id])
        #expect(model.loginSessions == [thisPhone])
        #expect(!model.hasOtherSessions)
    }

    @Test("登出其他所有裝置後只剩這台")
    func signOutOtherSessions() async {
        let repository = InMemoryAccountSecurityRepository.sample()
        let model = AccountSecurityModel(repository: repository)
        await model.load()

        await model.signOutOtherSessions()

        #expect(await repository.signedOutOthersCount == 1)
        #expect(model.loginSessions == [thisPhone])
    }

    @Test("登出裝置失敗時照顯示後端訊息")
    func signOutFailure() async {
        let repository = InMemoryAccountSecurityRepository.sample()
        let model = AccountSecurityModel(repository: repository)
        await model.load()
        await repository.fail(with: .rejected("找不到此裝置工作階段"))

        await model.signOut(webBrowser)

        #expect(model.alertMessage == "找不到此裝置工作階段")
    }

    @Test("確認訊息帶裝置名稱")
    func signOutConfirmation() {
        let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository.sample())

        #expect(model.signOutConfirmation(for: webBrowser) == "確定要登出「Chrome · macOS」嗎？那台裝置需要重新登入。")
    }

    @Test("時間用台灣時間的「年/月/日 時:分」")
    func timeText() {
        #expect(AccountSecurityModel.timeText(Date(timeIntervalSince1970: 1_794_716_050)) == "2026/11/15 12:14")
    }

    @Test("新密碼至少 6 個字元、目前密碼要填,才能送出")
    func passwordValidation() {
        let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository.sample())
        #expect(!model.canChangePassword)

        model.currentPassword = "old-secret"
        model.newPassword = "12345"
        #expect(!model.canChangePassword)

        model.newPassword = "123456"
        #expect(model.canChangePassword)

        model.currentPassword = ""
        #expect(!model.canChangePassword)
    }

    @Test("修改密碼成功:提示其他裝置已登出,清空欄位,清單只剩這台")
    func changePasswordSucceeds() async {
        let repository = InMemoryAccountSecurityRepository.sample()
        let model = AccountSecurityModel(repository: repository)
        await model.load()
        model.currentPassword = "old-secret"
        model.newPassword = "new-secret"

        await model.changePassword()

        #expect(await repository.passwordChanges.map(\.new) == ["new-secret"])
        #expect(await repository.passwordChanges.map(\.current) == ["old-secret"])
        #expect(model.passwordChangedMessage == "密碼已更新，其他裝置已登出")
        #expect(model.currentPassword.isEmpty)
        #expect(model.newPassword.isEmpty)
        #expect(model.loginSessions == [thisPhone])
    }

    @Test("目前密碼錯誤、嘗試次數過多:照顯示後端訊息,欄位保留")
    func changePasswordRejected() async {
        for error in [
            RepositoryError.invalidCredentials("目前密碼錯誤"), RepositoryError.rejected("嘗試次數過多，請於 15 分鐘後再試"),
        ] {
            let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository(
                sessions: [thisPhone], failure: error
            ))
            model.currentPassword = "wrong"
            model.newPassword = "new-secret"

            await model.changePassword()

            #expect(model.passwordErrorMessage == error.localizedDescription)
            #expect(model.passwordChangedMessage == nil)
            #expect(model.newPassword == "new-secret")
        }
    }

    @Test("送出期間不能再送一次", .timeLimit(.minutes(1)))
    func changingPasswordDisablesSubmit() async {
        let gate = Gate()
        let model = AccountSecurityModel(repository: InMemoryAccountSecurityRepository(sessions: [thisPhone], gate: gate))
        model.currentPassword = "old-secret"
        model.newPassword = "new-secret"

        let submission = Task { await model.changePassword() }
        await gate.waitUntilReached()
        #expect(model.isChangingPassword)
        #expect(!model.canChangePassword)

        await gate.open()
        await submission.value
        #expect(!model.isChangingPassword)
    }
}
