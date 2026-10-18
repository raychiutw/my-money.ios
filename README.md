# 我的記帳本

家庭與個人一起用的記帳 App。夫妻與家庭成員各自記帳，家裡的錢和自己的錢分得清清楚楚，打開就知道現在真正能花的有多少、接下來兩個月的錢夠不夠用。

這是 [我的記帳本網頁版](https://github.com/onion523/my-money) 的 iOS App，和網頁版共用同一個帳號與資料，支援 iPhone 與 iPad。

<table>
  <tr>
    <td align="center"><img src="docs/readme/overview.png" width="200" alt="總覽"><br>總覽</td>
    <td align="center"><img src="docs/readme/transactions.png" width="200" alt="收支明細"><br>收支明細</td>
    <td align="center"><img src="docs/readme/quick-entry-recommended.png" width="200" alt="記一筆，分類自動推薦"><br>記一筆，分類自動推薦</td>
    <td align="center"><img src="docs/readme/statistics.png" width="200" alt="統計與分攤建議"><br>統計與分攤建議</td>
  </tr>
</table>

## 功能特色

### 🏠 家裡的錢、自己的錢分開看

- 每一筆收支明細都標成「家庭公帳」或「個人私帳」
- 總覽、統計與現金流預測都能切換「全部」「家庭公帳」「個人私帳」三種範圍
- 家庭成員記的家庭公帳也看得到，每一筆是誰記的、記在哪個帳戶一目了然；個人私帳只有自己看得到
- 用自己的錢替家裡代墊的支出會記下來，之後由家庭撥款報銷

### 💰 一眼看懂現在能花多少

- **淨可用餘額**：現金加活存帳戶，扣掉信用卡待繳款
- **真實可支配現金**：再扣掉週期支出的每月平均（房租這類月繳照算，年繳、季繳攤成每月金額），以及儲蓄目標的每月預留
- **當月淨收支**與**信用卡待繳**；有分類超出預算時，首頁會提醒超支的分類數，點一下就能看是哪些分類
- 首頁列出接下來 60 天最近 5 筆預定收支，繳完一筆勾一筆；完整清單在現金流預測

### ✍️ 記帳又快又準

- 記一筆只要選帳戶、輸入金額；打上備註，分類會依照過去記過的相同備註或備註裡的關鍵字自動推薦
- 收支明細可以按月份快速切換，依帳戶、分類、類型篩選，也能搜尋備註
- 每天的支出長條圖和「支出佔收入」比例，馬上看出哪天花最多
- 收支明細可以匯出成 CSV

<table>
  <tr>
    <td align="center"><img src="docs/readme/accounts.png" width="200" alt="帳戶"><br>帳戶</td>
    <td align="center"><img src="docs/readme/card-detail.png" width="200" alt="信用卡"><br>信用卡</td>
    <td align="center"><img src="docs/readme/forecast.png" width="200" alt="現金流預測"><br>現金流預測</td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="docs/readme/recurring.png" width="200" alt="週期收支"><br>週期收支</td>
    <td align="center"><img src="docs/readme/goals.png" width="200" alt="儲蓄目標"><br>儲蓄目標</td>
    <td align="center"><img src="docs/readme/household-joined.png" width="200" alt="家庭"><br>家庭</td>
  </tr>
</table>

### 💳 現金、活存帳戶與信用卡

- 現金、活存帳戶與信用卡分開管理，ATM 提款與帳戶間轉帳也能記
- 信用卡會記住結帳日與繳款日，分開顯示已出帳待繳款與未出帳款
- 結帳日可以先預覽這期要出帳的消費，逐筆決定要不要延到下一期
- 信用卡繳款可以選「繳家庭代墊」「繳個人私帳」或「全額結清」

### 📅 週期收支與儲蓄目標

- 房租、保費、訂閱這類週期收支設定一次，不論每月、每季、每半年或每年繳，都會換算成每月平均
- 設定儲蓄目標與截止日，隨時存入、看達成率

### 📊 統計、預算與現金流預測

- 每個月的支出分類圓餅圖與全年收支趨勢
- 為各分類設定預算，超支馬上知道
- **現金流預測**：推算未來 60 天每天的餘額，提早看出哪一天可能不夠用；大筆消費前也能用「購買力試算」，看會不會透支、會不會影響儲蓄目標

### 👨‍👩‍👧 家庭

- 建立家庭並邀請家庭成員加入，家庭管理員與一般成員權限不同
- 家庭公帳的收支、帳戶與週期收支大家一起看

### 🤖 用聊天機器人記帳

綁定 LINE 或 Telegram 機器人，傳一句話就能記一筆。

### 🌙 舒服好讀

- 支援深色模式、系統文字大小與 VoiceOver
- iPad 版內容置中、不會拉得太寬，橫放時可用側邊欄切換各頁

<table>
  <tr>
    <td align="center"><img src="docs/readme/overview-dark.png" width="200" alt="深色模式：總覽"></td>
    <td align="center"><img src="docs/readme/transactions-dark.png" width="200" alt="深色模式：收支明細"></td>
    <td align="center"><img src="docs/readme/statistics-dark.png" width="200" alt="深色模式：統計"></td>
    <td align="center"><img src="docs/readme/forecast-dark.png" width="200" alt="深色模式：現金流預測"></td>
  </tr>
</table>

> 截圖使用範例資料。
