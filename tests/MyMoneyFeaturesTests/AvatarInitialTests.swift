import MyMoneyFeatures
import Testing

@Suite("「我的」頭像的文字")
struct AvatarInitialTests {
    @Test("中文姓名取第一個字")
    func chineseNameUsesFirstCharacter() {
        #expect(AvatarInitial.text(for: "王小明") == "王")
    }

    @Test("英文姓名取第一個字母並轉大寫")
    func latinNameUsesUppercasedFirstLetter() {
        #expect(AvatarInitial.text(for: "alice") == "A")
        #expect(AvatarInitial.text(for: "éclair") == "É")
    }

    @Test("姓名前後的空白不算，取第一個看得見的字元")
    func surroundingWhitespaceIsIgnored() {
        #expect(AvatarInitial.text(for: "  bob ") == "B")
        #expect(AvatarInitial.text(for: "\n小美\t") == "小")
    }

    @Test("姓名是空的或只有空白時沒有文字，畫面改用人像圖示")
    func blankNameHasNoText() {
        #expect(AvatarInitial.text(for: "") == nil)
        #expect(AvatarInitial.text(for: "   \n") == nil)
    }

    @Test("第一個字元是由多個 Unicode 純量組成的符號(例如家庭 emoji)時，整個符號算一個字元")
    func graphemeClusterCountsAsOneCharacter() {
        #expect(AvatarInitial.text(for: "👨‍👩‍👧 家人") == "👨‍👩‍👧")
    }
}
