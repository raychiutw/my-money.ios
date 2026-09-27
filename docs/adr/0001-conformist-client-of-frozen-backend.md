---
status: accepted
---

# iOS 是凍結後端的 Conformist client,功能與 web 對等

後端 [`onion523/my-money`](https://github.com/onion523/my-money) 不是我們的 repo(只有 pull 權限),而且大部分業務規則都在後端:餘額、現金流預測、購買力評估、家庭範圍、超支判斷都由 API 算好回傳。所以 iOS **不改後端**,只當另一個 client,依 Evans 的定義採 **Conformist**:沿用後端的模型與 `CONTEXT.md` 的詞彙，不在 iOS 另外發明一套模型、也不在本機重算規則。wire format 的雜亂(snake_case 和 camelCase 混用、0/1 和 true/false 混用、envelope 格式、`balance` 一詞兩義)全部收在一個薄的翻譯 seam(`MyMoneyAPI`)裡處理，DTO 不出這一層。

產品規則是「**功能層與 web 對等，互動層照 HIG 轉譯，照抄程式流程,bug 不照抄**」:
- web 沒有的功能不加，例如 Face ID 鎖定、Widget、通知、離線、刪除帳號、Sign in with Apple。
- web 的呈現方式照 iOS 慣例轉譯，例如 Modal 改成 sheet、`window.confirm` 改成 confirmation dialog、主題切換鈕移除改為跟隨系統、CSV 下載改成 ShareLink。
- 純前端的 bug 用現有 API 修正;後端造成的行為避不開，只能照舊。每一處偏離都列在 `docs/parity.md`,並彙整成一個 issue 回報給 web。

## Considered Options

- **發 PR 修後端**:沒有 push 權限，後端也不歸我們管。
- **完整的 Anticorruption Layer**(iOS 有自己的 domain model):後端凍結，隔離上游改版這個最大的好處就不存在了;而 iOS 另建一套模型，只會讓 iOS 和 web 分岔。
- **純 Conformist,不做翻譯層**:`balance` 的一詞兩義和 0/1 旗標會散到每個畫面，詞彙表形同虛設。

## Consequences

- **不能上 App Store**:Review Guideline 5.1.1(v) 規定 app 內能註冊就必須能刪除帳號，但後端沒有刪除帳號的 endpoint。v1 只走 TestFlight 內部測試，測試者必須是開發者團隊的 App Store Connect 使用者;等後端補上刪除帳號，才能轉上架。
- 後端的 bug 在 iOS 上會一樣出現，例如編輯或刪除交易不回沖餘額、預測週期判斷錯誤、預測只算個人帳戶。修正要等上游處理。
- 開發直接連 prod API,只用專用測試帳號，這個帳號不加入任何家庭。
