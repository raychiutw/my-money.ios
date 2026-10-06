import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("儲蓄目標的建立與編輯")
struct SavingsGoalEditorTests {
    private let repository = InMemorySavingsGoalRepository.sample()
    private let dataVersion = DataVersion()
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func adding() -> SavingsGoalEditorModel {
        SavingsGoalEditorModel(adding: (), repository: repository, dataVersion: dataVersion, today: { today })
    }

    private func editing(_ index: Int) -> SavingsGoalEditorModel {
        SavingsGoalEditorModel(
            editing: InMemorySavingsGoalRepository.sampleGoals[index], repository: repository, dataVersion: dataVersion,
            today: { today }
        )
    }

    @Test("建立的預設值:目標圖示、沒有截止日;圖示有 12 種可選")
    func defaults() {
        let editor = adding()

        #expect(editor.title == "建立儲蓄目標")
        #expect(editor.icon == .target)
        #expect(!editor.hasDeadline)
        #expect(SavingsGoalIcon.allCases.count == 12)
        #expect(SavingsGoalIcon.allCases.first == .target)
    }

    @Test("名稱必填")
    func nameIsRequired() async {
        let editor = adding()
        editor.name = "   "
        editor.targetAmountText = "60000"

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入目標名稱")
    }

    @Test("目標金額要是正數", arguments: ["", "0", "-100", "abc", "1,000", "12.5"])
    func targetMustBePositive(amount: String) async {
        let editor = adding()
        editor.name = "買新筆電"
        editor.targetAmountText = amount

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入有效目標金額")
    }

    @Test("建立：每月預留沒填時是 0;打開截止日時送出選的日期")
    func create() async {
        let editor = adding()
        editor.icon = .laptop
        editor.name = " 買新筆電 "
        editor.targetAmountText = "45000"
        editor.hasDeadline = true
        editor.deadline = CalendarDay(year: 2027, month: 1, day: 31)

        #expect(await editor.save())

        #expect(await repository.createdDrafts == [SavingsGoalDraft(
            name: "買新筆電", icon: .laptop, targetAmount: Money(45000), monthlyReserve: .zero,
            deadline: CalendarDay(year: 2027, month: 1, day: 31)
        )])
        #expect(dataVersion.value == 1)
    }

    @Test("每月預留看不懂或是負數時當作 0", arguments: ["abc", "-500"])
    func invalidReserveIsZero(reserve: String) async {
        let editor = adding()
        editor.name = "買新筆電"
        editor.targetAmountText = "45000"
        editor.monthlyReserveText = reserve

        #expect(await editor.save())

        #expect(await repository.createdDrafts.first?.monthlyReserve == .zero)
    }

    @Test("編輯時帶入原值;關掉截止日等於移除截止日")
    func editingRemovesDeadline() async {
        let trip = InMemorySavingsGoalRepository.sampleGoals[0]
        let editor = editing(0)

        #expect(editor.title == "編輯儲蓄目標")
        #expect(editor.name == "沖繩旅遊")
        #expect(editor.icon == .plane)
        #expect(editor.targetAmountText == "60000")
        #expect(editor.monthlyReserveText == "5000")
        #expect(editor.hasDeadline)
        #expect(editor.deadline == CalendarDay(year: 2027, month: 3, day: 31))

        editor.hasDeadline = false
        #expect(await editor.save())

        #expect(await repository.updatedDrafts[trip.id]?.deadline == nil)
        #expect(dataVersion.value == 1)
    }

    @Test("沒有截止日的目標，打開截止日時預設今天")
    func deadlineDefaultsToToday() {
        let editor = editing(1)

        #expect(!editor.hasDeadline)
        #expect(editor.deadline == today)
    }
}

@Suite("儲蓄目標圖示的畫面對照(#195)")
struct SavingsGoalIconPresentationTests {
    @Test("每個圖示有 SF Symbol 與 VoiceOver 名稱,順序同 12 款預設圖示")
    func symbolsAndNames() {
        #expect(SavingsGoalIcon.allCases.map(\.title) == ["目標", "旅行", "住家", "汽車", "珠寶", "電腦", "寶寶", "學業", "健康", "度假", "背包", "藝術"])
        #expect(Set(SavingsGoalIcon.allCases.map(\.symbolName)).count == 12, "12 個符號彼此不同")
    }
}
