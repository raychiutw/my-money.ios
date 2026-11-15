import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("帳號安全:通行金鑰(passkey,#339)")
struct PasskeysTests {
    private let iPhone = InMemoryPasskeyRepository.iPhone
    private let mac = InMemoryPasskeyRepository.mac

    @Test("passkey 載入前是 nil(顯示骨架),載入後照後端順序列出")
    func load() async {
        let model = PasskeysModel(repository: InMemoryPasskeyRepository.sample())
        #expect(model.passkeys == nil)
        #expect(model.isLoading)

        await model.load()

        #expect(model.passkeys == [iPhone, mac])
        #expect(!model.isLoading)
    }

    @Test("載入失敗時顯示原因,不停在骨架")
    func loadFailure() async {
        let model = PasskeysModel(repository: InMemoryPasskeyRepository(passkeys: [], failure: RepositoryError.rejected("伺服器忙碌")))

        await model.load()

        #expect(model.errorMessage == "伺服器忙碌")
        #expect(!model.isLoading)
    }

    @Test("建立 passkey 帶名稱,成功後重新載入清單")
    func create() async {
        let repository = InMemoryPasskeyRepository(passkeys: [])
        let model = PasskeysModel(repository: repository)
        await model.load()

        await model.create(name: "  我的 iPad ")

        #expect(await repository.createdNames == ["我的 iPad"])
        #expect(model.passkeys?.map(\.name) == ["我的 iPad"])
        #expect(!model.isCreating)
    }

    @Test("建立時取消系統的 passkey 視窗:不顯示錯誤")
    func createCancelled() async {
        let repository = InMemoryPasskeyRepository.sample()
        let model = PasskeysModel(repository: repository)
        await model.load()
        await repository.fail(with: CancellationError())

        await model.create(name: "iPad")

        #expect(model.alertMessage == nil)
    }

    @Test("建立失敗時照顯示後端訊息")
    func createFailure() async {
        let repository = InMemoryPasskeyRepository.sample()
        let model = PasskeysModel(repository: repository)
        await model.load()
        await repository.fail(with: RepositoryError.rejected("Passkey 註冊驗證失敗"))

        await model.create(name: "iPad")

        #expect(model.alertMessage == "Passkey 註冊驗證失敗")
    }

    @Test("建立期間按鈕停用")
    func creatingState() async {
        let gate = Gate()
        let model = PasskeysModel(repository: InMemoryPasskeyRepository(passkeys: [], gate: gate))

        let creation = Task { await model.create(name: "iPad") }
        await gate.waitUntilReached()
        #expect(model.isCreating)

        await gate.open()
        await creation.value
        #expect(!model.isCreating)
    }

    @Test("改名後重新載入清單;空白名稱不送出")
    func rename() async {
        let repository = InMemoryPasskeyRepository.sample()
        let model = PasskeysModel(repository: repository)
        await model.load()

        await model.rename(mac, to: "   ")
        await model.rename(mac, to: " 工作用 Mac ")

        #expect(await repository.renames == [InMemoryPasskeyRepository.Rename(id: mac.id, name: "工作用 Mac")])
        #expect(model.passkeys?.map(\.name) == ["iPhone", "工作用 Mac"])
    }

    @Test("刪除後重新載入清單;失敗時照顯示後端訊息")
    func delete() async {
        let repository = InMemoryPasskeyRepository.sample()
        let model = PasskeysModel(repository: repository)
        await model.load()

        await model.delete(mac)
        #expect(model.passkeys == [iPhone])

        await repository.fail(with: RepositoryError.rejected("找不到指定的 Passkey"))
        await model.delete(iPhone)
        #expect(model.alertMessage == "找不到指定的 Passkey")
    }

    @Test("刪除確認訊息帶名稱,說明已登入的裝置不受影響")
    func deleteConfirmation() {
        let model = PasskeysModel(repository: InMemoryPasskeyRepository.sample())

        #expect(model.deleteConfirmation(for: mac) == "確定要刪除「MacBook」嗎？之後就不能再用它登入，已登入的裝置不受影響。")
    }
}

