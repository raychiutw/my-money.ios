# MyMoneyAPITests fixtures

翻譯層(Seam 2)的測試只吃這裡的 fixture。每一份都是用專用測試帳號從 **prod** 錄下的**真實回應**,不照程式碼手寫(`CLAUDE.md`「測試慣例」)。測試用 `URLProtocol` stub 把 fixture 當成 HTTP body 回給 `APIClient`,HTTP 狀態碼寫在測試裡，對照下表。

## 測試帳號

- Email:`mymoney-ios-test@example.com`,名稱「iOS 測試帳號」。**不加入任何家庭**,所以錄到的資料只有這個帳號自己的。
- 密碼不進 repo。錄製腳本依序讀:
  1. 環境變數 `MYMONEY_TEST_PASSWORD`
  2. 本機 macOS Keychain:service `my-money-ios-test`、account `mymoney-ios-test@example.com`

  ```bash
  # 在新的 Mac 上設定(密碼向維護者索取):
  security add-generic-password -s my-money-ios-test -a mymoney-ios-test@example.com -w '<密碼>'
  ```

## 錄製流程

```bash
scripts/record-fixture.sh <fixture 檔名> <METHOD> <path> [JSON body] [--no-auth | --bad-token]
```

1. 先讀後端 [`onion523/my-money@43a205d`](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers) 對應的 handler,確認這個請求會寫入什麼。只寫測試帳號自己的資料，不碰別人的資料，也不建立或加入家庭。
2. 執行腳本。預設會先登入測試帳號，再帶 `Authorization: Bearer` 呼叫;`/auth/*` 用 `--no-auth`,錄 401 用 `--bad-token`。
   - body 裡寫 `__EMAIL__`、`__PASSWORD__`,腳本會換成測試帳號的 email 與密碼，所以密碼不會出現在指令列或 shell history。
   - 腳本會把回應裡所有 JWT 換成假值 `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ZmFrZS1maXh0dXJlLXRva2Vu.ZmFrZS1zaWduYXR1cmU`,並在回應含有密碼時拒絕存檔。
   - 腳本會印出 HTTP 狀態碼與 Content-Type,把它填進下表。
3. 用 `git diff` 看一次存下來的內容：不能有真的 token、密碼或其他人的資料。
4. 在下表補一列，再寫測試。

**只能成功一次的請求**(例如註冊)要特別小心：腳本會先確認寫得進 fixture 檔再打 API,但錄之前還是先確認指令沒打錯。

## 清單

錄製日期都是 2026-09-28,後端版本 `43a205d`。

| fixture | 請求 | HTTP | 用來驗證 |
|---|---|---|---|
| `auth-login-success.json` | `POST /auth/login`,正確的密碼 | 200 | `{success, data}` 解碼成 session |
| `auth-login-wrong-password.json` | `POST /auth/login`,錯誤的密碼 | 401 | `/auth/*` 的 401 原樣傳遞「Email 或密碼錯誤」,不算 session 過期 |
| `auth-login-malformed-body.txt` | `POST /auth/login`,body 是 `not-json` | 500,`text/plain` | 回應不是 JSON 時顯示「伺服器無回應」 |
| `accounts-invalid-token.json` | `GET /accounts`,帶無效的 token | 401 | 非 `/auth/*` 的 401 是 session 過期 |
| `bot-bindings-delete.json` | `DELETE /bot/bindings/fixture-nonexistent-binding` | 200 | 只有 `{success, message}` 的 envelope 視為成功(這個 id 不存在，不會刪到任何資料) |
| `auth-register-email-taken.json` | `POST /auth/register`,用測試帳號已經註冊過的 email | 409 | 「此 Email 已被使用」原樣傳遞(不會建立任何資料) |
| `accounts-list-empty.json` | `GET /accounts`,測試帳號還沒有任何資金帳戶時 | 200 | 空清單 |
| `accounts-create-bank.json` | `POST /accounts`,建立銀行存款帳戶「iOS 測試存款」(餘額 50000) | 201 | 建立後的回應(#7 使用) |
| `accounts-create-credit-card.json` | `POST /accounts`,建立信用卡帳戶「iOS 測試信用卡」(已出帳 12000、未出帳 3500、額度 100000) | 201 | 建立後的回應(#7 使用) |
| `accounts-create-credit-card-low-limit.json` | `POST /accounts`,建立信用卡帳戶「iOS 測試小額卡」(已出帳 8000、未出帳 5000、額度 20000) | 201 | 建立後的回應(#7 使用) |
| `accounts-list.json` | `GET /accounts`,上面三個資金帳戶建立之後 | 200 | snake_case;`balance` 依類型拆成餘額或已出帳待繳金額;含 `is_joint`、`shared_debt`、`personal_debt` |
| `accounts-balance.json` | `GET /accounts/balance`,同上 | 200 | camelCase 的資金指標(淨可用資產 21500) |
| `accounts-update.json` | `PUT /accounts/:id`,用暫時建立的資金帳戶(改名、改餘額、`is_joint: 1`),錄完就刪掉 | 200 | 編輯成功(回傳更新後的資料列) |
| `accounts-delete.json` | `DELETE /accounts/:id`,刪除上面那個暫時帳戶 | 200 | `{success, data: null}` 視為成功 |
| `accounts-delete-not-found.json` | 再刪一次同一個 id | 404 | 「帳戶不存在」原樣傳遞 |
| `transactions-create-shared-expense.json` | `POST /transactions`,「iOS 測試存款」家庭公帳支出 餐飲 120「午餐」 | 201 | 記一筆成功 |
| `transactions-create-private-expense.json` | `POST /transactions`,「iOS 測試信用卡」個人私帳支出 購物 880「耳機」 | 201 | 記一筆成功 |
| `transactions-create-income.json` | `POST /transactions`,「iOS 測試存款」收入 薪資 45000 | 201 | 記一筆成功 |
| `transactions-recent.json` | `GET /transactions?scope=all&limit=6&offset=0`,不帶 `from` / `to`(總覽的最近 6 筆) | 200 | 不限日期，由新到舊 |
| `transactions-list.json` | `GET /transactions?from=2026-09-01&to=2026-09-30&scope=all&limit=200&offset=0` | 200 | `is_shared` 0/1、`account_name`、`user_name`;日期由新到舊 |
| `transactions-create-missing-fields.json` | `POST /transactions`,沒有 `account_id` | 400 | 「請填寫必填欄位」原樣傳遞 |
| `transactions-update.json` | `PUT /transactions/:id`,用暫時記的一筆(改成 75 元、個人私帳),錄完就刪掉 | 200 | 編輯成功 |
| `transactions-delete.json` | `DELETE /transactions/:id`,刪除上面那筆 | 200 | `{success, data: null}` 視為成功 |
| `transactions-delete-not-found.json` | 再刪一次同一個 id | 404 | 「紀錄不存在」原樣傳遞 |
| `export-transactions.csv` | `GET /export/csv?from=2026-09-01&to=2026-09-30` | 200,`text/csv` | UTF-8 加 BOM 的 CSV 原樣回傳(不是 JSON envelope) |
| `recurring-create-rent.json` | `POST /recurring`,固定支出「房租」12000,每月 5 號，關聯「iOS 測試存款」 | 201 | 新增成功 |
| `recurring-create-insurance.json` | `POST /recurring`,固定支出「年繳保費」24000,每年 15 號，不指定關聯帳戶 | 201 | `account_id` 是 `null` |
| `recurring-create-salary.json` | `POST /recurring`,固定收入「薪水」45000,每月 25 號，關聯「iOS 測試存款」 | 201 | 新增成功 |
| `recurring-create-missing-name.json` | `POST /recurring`,沒有 `name` | 400 | 「請填寫所有必填欄位」原樣傳遞 |
| `recurring-list.json` | `GET /recurring`,上面三項建立之後 | 200 | snake_case;`account_id` 可以是 `null`;JOIN 的 `account_name` |
| `recurring-amortize.json` | `GET /recurring/amortize`,同上 | 200 | 後端算好的 `monthly_expense` 14000、`monthly_income` 45000 |
| `recurring-update.json` | `PUT /recurring/:id`,用暫時建立的項目(改成每半年 20 號 360),錄完就刪掉 | 200 | 編輯成功(回傳更新後的資料列) |
| `recurring-delete.json` | `DELETE /recurring/:id`,刪除上面那個暫時項目 | 200 | `{success, data: null}` 視為成功 |
| `recurring-delete-not-found.json` | 再刪一次同一個 id | 404 | 「項目不存在」原樣傳遞 |
| `export-recurring.csv` | `GET /export/recurring` | 200,`text/csv` | UTF-8 加 BOM 的 CSV 原樣回傳 |
| `goals-list-empty.json` | `GET /goals`,測試帳號還沒有任何儲蓄目標時 | 200 | 空清單 |
| `goals-create-trip.json` | `POST /goals`,✈️「沖繩旅遊」60000,每月預留 5000,截止日 2027-03-31 | 201 | 建立成功 |
| `goals-create-emergency.json` | `POST /goals`,🏥「緊急備用金」100000,沒有每月預留與截止日 | 201 | `deadline` 是 `null` |
| `goals-create-missing-name.json` | `POST /goals`,沒有 `name` | 400 | 「請填寫目標名稱和金額」原樣傳遞 |
| `goals-deposit.json` | `POST /goals/:id/deposit {amount: 3000}`,存入「沖繩旅遊」 | 200 | 回傳更新後的目標(已存 3000) |
| `goals-deposit-capped.json` | 用暫時建立的 🎒「iOS 小目標」(目標 1000)存入 5000 | 200 | 後端把已存金額卡在目標金額 1000 |
| `goals-deposit-invalid.json` | `POST /goals/:id/deposit {amount: 0}` | 400 | 「金額必須大於 0」原樣傳遞 |
| `goals-list.json` | `GET /goals`,上面三個目標建立並存入之後 | 200 | snake_case;`deadline` 可以是 `null`;含已達成的目標 |
| `goals-update.json` | `PUT /goals/:id`,改暫時目標(改名、改 emoji、不送 `deadline`),錄完就刪掉 | 200 | 沒送 `deadline` 時後端清成 `null`;已存金額不變(後端的 PUT 不動 `saved_amount`) |
| `goals-delete.json` | `DELETE /goals/:id`,刪除上面那個暫時目標 | 200 | `{success, data: null}` 視為成功 |
| `goals-delete-not-found.json` | 再刪一次同一個 id | 404 | 「目標不存在」原樣傳遞 |
| `stats-category.json` | `GET /transactions/summary/category?month=2026-09&scope=all` | 200 | 依金額由大到小(購物 880、餐飲 120),不含「信用卡還款」 |
| `stats-category-personal.json` | 同上，`scope=personal` | 200 | 我記的支出(已花的來源之一) |
| `stats-category-empty.json` | 同上，`month=2026-08` | 200 | 空清單 |
| `stats-monthly.json` | `GET /transactions/summary/monthly?year=2026&scope=all` | 200 | 每個月的收入、支出各一列(`month`、`type`、`total`) |
| `stats-household-shares-empty.json` | `GET /transactions/summary/household-shares?month=2026-09`,測試帳號沒有家庭群組時 | 200 | 空清單 |
| `stats-household-shares.json` | 同上。先讓測試帳號自己建立一個只有自己的家庭群組「iOS 測試家庭」,錄完就離開(最後一位成員離開時，後端會刪掉整個家庭群組) | 200 | `user_id`、`user_name`、`total`;兩人的分攤建議用單元測試驗證 |
| `budgets-list-empty.json` | `GET /budgets?month=2026-09`,還沒有任何分類預算時 | 200 | 空清單 |
| `budgets-put-create.json` | `PUT /budgets`,餐飲 5000(新增) | 200 | 回傳設定後的資料列 |
| `budgets-put-update.json` | `PUT /budgets`,餐飲改成 100(同分類同月份會調整原本那筆) | 200 | 同一個 `id` |
| `budgets-put-missing-amount.json` | `PUT /budgets`,沒有 `amount` | 400 | 「請填寫所有欄位」原樣傳遞 |
| `budgets-list.json` | `GET /budgets?month=2026-09`,餐飲 100、購物 1000 設定之後 | 200 | 後端算好的 `spent` 與 `over`(餐飲超支、購物 88%)。分類預算無法刪除，會留在測試帳號的 2026-09 |
| `forecast.json` | `GET /forecast`,台灣時間 2026-09-28 早上錄的 | 200 | camelCase;30 天逐日餘額、`minBalance`、`minDate`、`willOverdraft`、預定收支(房租、薪水)。第一天是 2026-09-27,因為後端用 UTC 的今天(後端造成的第 14 項) |
| `forecast-purchase-safe.json` | `POST /forecast/purchase-check {amount: 1000}` | 200 | 放心購買;`affectedGoals` 列出所有有每月預留的儲蓄目標，不管評估結果是哪一種 |
| `forecast-purchase-caution.json` | 同上 `{amount: 50000}`。錄之前先把「沖繩旅遊」的每月預留暫時改成 20000,錄完改回 5000 | 200 | 審慎評估(`affectsSavings: true`) |
| `forecast-purchase-danger.json` | 同上 `{amount: 60000}` | 200 | 不建議購買，最低餘額 -6560 |
| `bot-bindings-empty.json` | `GET /bot/bindings`,測試帳號還沒有機器人綁定時 | 200 | 空清單 |
| `bot-pairing-code.json` | `POST /bot/pairing-code` | 200 | 6 碼大寫英數的綁定驗證碼、`expires_in_seconds: 600` |
| `bot-simulate-missing-text.json` | `POST /bot/test-simulate {text: "", platform: "line"}` | 400 | 「請輸入測試訊息」原樣傳遞 |
| `bot-simulate-expense.json` | 同上 `{text: "午餐 120"}`。**會在測試帳號寫入一筆真的交易紀錄**(預期的結果) | 200 | `reply` 是機器人的回覆文字 |
| `bot-simulate-query.json` | 同上 `{text: "查帳"}` | 200 | 查帳不寫入任何資料 |
| `bot-bindings.json` | `GET /bot/bindings`,模擬對話之後 | 200 | 後端會自動建立「模擬測試助手」的 LINE 綁定 |
| `bot-unbind.json` | `DELETE /bot/bindings/:id`,解除上面那個綁定;錄完測試帳號回到沒有綁定 | 200 | 只回 `{success, message}` |
| `households-current-none.json` | `GET /households/current`,測試帳號沒有家庭群組時 | 200 | `household: null`、`myRole: null` |
| `households-join-invalid.json` | `POST /households/join {code: "FAM-0000"}`。0 不在後端的邀請碼字元表裡，這組不可能存在，不會誤加入別人的家庭 | 404 | 「邀請碼無效或已過期」原樣傳遞 |
| `households-create-missing-name.json` | `POST /households {name: "  "}` | 400 | 「請輸入家庭名稱」原樣傳遞 |
| `households-create.json` | `POST /households {name: "iOS 測試家庭"}`,測試帳號自己建立 | 201 | 我是管理員 |
| `households-current.json` | `GET /households/current`,上面那個家庭群組 | 200 | 成員名冊：`user_id`、`role`、`joined_at`(UTC 的 `YYYY-MM-DD HH:MM:SS`)、`name`、`email` |
| `households-invite.json` | `POST /households/invite` | 200 | `code` 是 `FAM-XXXX`,`expires_at` 是有毫秒的 ISO 8601 |
| `households-join-already-member.json` | 已經在家庭群組裡時 `POST /households/join` | 400 | 「你已經加入家庭群組，無法重複加入」原樣傳遞 |
| `households-remove-self.json` | 管理員 `DELETE /households/members/自己` | 400 | 「請使用離開家庭功能」原樣傳遞 |
| `households-leave.json` | `DELETE /households/leave`。測試帳號是唯一的成員，離開後後端會刪掉整個家庭群組 | 200 | 只回 `{success, message}`,沒有 `data` |
| `households-leave-none.json` | 再離開一次 | 400 | 「你未加入任何家庭」原樣傳遞 |
| `forecast-purchase-invalid.json` | 同上 `{amount: 0}` | 400 | 「請輸入有效金額」原樣傳遞 |

### 從缺:`auth-register-success.json`

2026-09-28 用 `POST /auth/register` 註冊測試帳號時，當時的腳本沒有先建立 `Fixtures/` 目錄，後端回了成功(429 bytes),回應卻沒寫進檔案。註冊同一個 email 只能成功一次，之後只會回 409「此 Email 已被使用」。腳本已經修正成先確認寫得進檔案再打 API。

要補錄註冊成功的回應，得再註冊一個專用 email,需要維護者同意。在那之前，註冊成功的解碼測試沿用 `auth-login-success.json`:後端 `/auth/register` 與 `/auth/login` 回傳的 `data` 形狀相同(`{token, user: {id, email, name}}`)。

### 從缺:加入家庭成功、移除成員成功

兩者都需要第二個帳號:加入得有別人的邀請碼，移除得有另一位一般成員。測試帳號只能加入自己建立的測試家庭，註冊第二個帳號需要維護者同意，所以沒有錄。

- `POST /households/join` 成功時，iOS 只看 `success`,不讀 `data`。
- `DELETE /households/members/:userId` 成功時回 `{success, message}`,形狀跟 `households-leave.json` 一樣。
