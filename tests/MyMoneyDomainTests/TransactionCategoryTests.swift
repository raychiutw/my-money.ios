import MyMoneyDomain
import Testing

@Suite("標準分類清單(上游 ADR-0009)")
struct TransactionCategoryTests {
    @Test("支出分類是 16 種，順序與上游一致")
    func expenseCategories() {
        #expect(TransactionCategory.expenseCategories.map(\.name) == [
            "餐飲", "交通", "汽機車輛", "居家水電", "數位訂閱", "購物", "生活", "娛樂",
            "美妝保養", "醫療", "教育", "寵物毛孩", "旅行度假", "社交人情", "保險稅費", "其他",
        ])
    }

    @Test("收入分類是 8 種，順序與上游一致")
    func incomeCategories() {
        #expect(TransactionCategory.incomeCategories.map(\.name) == [
            "薪資", "獎金", "投資", "兼職", "政府補貼", "禮金餽贈", "二手出清", "其他",
        ])
    }

    @Test("系統分類仍是 4 種，不在支出或收入的選擇清單裡")
    func systemCategories() {
        #expect(TransactionCategory.systemCategories.map(\.name).sorted() == ["ATM提款", "信用卡還款", "公帳代墊報銷", "內部轉帳"].sorted())
        let selectable = Set(TransactionCategory.expenseCategories + TransactionCategory.incomeCategories)
        #expect(selectable.isDisjoint(with: TransactionCategory.systemCategories))
    }
}
