import MyMoneyDomain
import MyMoneyFeatures
import Testing

@Suite("分類圖示(DESIGN.md「分類圖示」)")
struct CategorySymbolTests {
    @Test("支出 16 種分類各有專屬圖示，彼此不重複")
    func expenseSymbols() {
        let symbols = TransactionCategory.expenseCategories.map(\.symbolName)
        #expect(!symbols.contains("tag"), "有支出分類沒有專屬圖示:\(symbols)")
        #expect(Set(symbols).count == symbols.count, "支出分類的圖示有重複:\(symbols)")
    }

    @Test("收入 8 種分類各有專屬圖示，彼此不重複")
    func incomeSymbols() {
        let symbols = TransactionCategory.incomeCategories.map(\.symbolName)
        #expect(!symbols.contains("tag"), "有收入分類沒有專屬圖示:\(symbols)")
        #expect(Set(symbols).count == symbols.count, "收入分類的圖示有重複:\(symbols)")
    }

    @Test("支出與收入都有的「其他」用同一個圖示")
    func otherIsShared() {
        #expect(TransactionCategory("其他").symbolName == "shippingbox")
    }

    @Test("清單以外的分類(例如舊版機器人寫入的「副業」)用通用標籤圖示，歷史資料不遷移")
    func legacyCategoryFallsBack() {
        #expect(TransactionCategory("副業").symbolName == "tag")
    }

    @Test("新增的分類用對應的圖示", arguments: [
        ("汽機車輛", "car"), ("居家水電", "bolt.fill"), ("數位訂閱", "iphone"), ("美妝保養", "paintbrush.pointed"),
        ("寵物毛孩", "pawprint"), ("旅行度假", "airplane"), ("社交人情", "person.2"), ("保險稅費", "doc.text"),
        ("政府補貼", "building.columns"), ("禮金餽贈", "envelope"), ("二手出清", "arrow.3.trianglepath"),
    ])
    func newCategorySymbols(name: String, symbol: String) {
        #expect(TransactionCategory(name).symbolName == symbol)
    }
}
