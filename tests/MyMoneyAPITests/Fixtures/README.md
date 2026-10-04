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

1. 先讀後端 [`onion523/my-money@97f4789`](https://github.com/onion523/my-money/tree/97f4789/backend/src/handlers) 對應的 handler,確認這個請求會寫入什麼。只寫測試帳號自己的資料，不碰別人的資料，也不建立或加入家庭。
2. 執行腳本。預設會先登入測試帳號，再帶 `Authorization: Bearer` 呼叫;`/auth/*` 用 `--no-auth`,錄 401 用 `--bad-token`。
   - body 裡寫 `__EMAIL__`、`__PASSWORD__`,腳本會換成測試帳號的 email 與密碼，所以密碼不會出現在指令列或 shell history。
   - 腳本會把回應裡所有 JWT 換成假值 `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ZmFrZS1maXh0dXJlLXRva2Vu.ZmFrZS1zaWduYXR1cmU`,並在回應含有密碼時拒絕存檔。
   - 腳本會印出 HTTP 狀態碼與 Content-Type,把它填進下表。
3. 用 `git diff` 看一次存下來的內容：不能有真的 token、密碼或其他人的資料。
4. 在下表補一列，再寫測試。

**只能成功一次的請求**(例如註冊)要特別小心：腳本會先確認寫得進 fixture 檔再打 API,但錄之前還是先確認指令沒打錯。

## 清單

這張表的錄製日期都是 2026-09-28,後端版本 `43a205d`;之後重錄或新增的，在後面各個「對齊上游」小節註明日期與後端版本。

| fixture | 請求 | HTTP | 用來驗證 |
|---|---|---|---|
| `auth-login-success.json` | `POST /auth/login`,正確的密碼 | 200 | `{success, data}` 解碼成 session |
| `auth-login-wrong-password.json` | `POST /auth/login`,錯誤的密碼 | 401 | `/auth/*` 的 401 原樣傳遞「Email 或密碼錯誤」,不算 session 過期 |
| `auth-login-malformed-body.txt` | `POST /auth/login`,body 是 `not-json` | 500,`text/plain` | 回應不是 JSON 時顯示「伺服器無回應」 |
| `accounts-invalid-token.json` | `GET /accounts`,帶無效的 token | 401 | 非 `/auth/*` 的 401 是 session 過期 |
| `bot-bindings-delete.json` | `DELETE /bot/bindings/fixture-nonexistent-binding` | 200 | 只有 `{success, message}` 的 envelope 視為成功(這個 id 不存在，不會刪到任何資料) |
| `auth-register-email-taken.json` | `POST /auth/register`,用測試帳號已經註冊過的 email | 409 | 「此 Email 已被使用」原樣傳遞(不會建立任何資料) |
| `accounts-list-empty.json` | `GET /accounts`,測試帳號還沒有任何資產帳戶時 | 200 | 空清單 |
| `accounts-create-bank.json` | `POST /accounts`,建立活存帳戶「iOS 測試存款」(餘額 50000) | 201 | 建立後的回應(#7 使用) |
| `accounts-create-credit-card.json` | `POST /accounts`,建立信用卡帳戶「iOS 測試信用卡」(已出帳 12000、未出帳 3500、額度 100000) | 201 | 建立後的回應(#7 使用) |
| `accounts-create-credit-card-low-limit.json` | `POST /accounts`,建立信用卡帳戶「iOS 測試小額卡」(已出帳 8000、未出帳 5000、額度 20000) | 201 | 建立後的回應(#7 使用) |
| `accounts-list-permission.json` | `GET /accounts`(2026-10-02,上游 `af5444c`) | 200 | 每個帳戶都有 `user_id`(擁有者)與 `is_joint`:編輯權限防呆(上游 ADR 0013、#133)用 |
| `accounts-list.json` | `GET /accounts`,上面三個資產帳戶建立之後 | 200 | snake_case;`balance` 依類型拆成餘額或已出帳待繳款;含 `is_joint`、`shared_debt`、`personal_debt` |
| `accounts-balance.json` | `GET /accounts/balance`,同上 | 200 | camelCase 的資金指標(淨可用餘額 21500) |
| `accounts-update.json` | `PUT /accounts/:id`,用暫時建立的資產帳戶(改名、改餘額、`is_joint: 1`),錄完就刪掉 | 200 | 編輯成功(回傳更新後的資料列) |
| `accounts-delete.json` | `DELETE /accounts/:id`,刪除上面那個暫時帳戶 | 200 | `{success, data: null}` 視為成功 |
| `accounts-delete-not-found.json` | 再刪一次同一個 id | 404 | 「帳戶不存在」原樣傳遞 |
| `transactions-create-shared-expense.json` | `POST /transactions`,「iOS 測試存款」家庭公帳支出 餐飲 120「午餐」 | 201 | 記一筆成功 |
| `transactions-create-private-expense.json` | `POST /transactions`,「iOS 測試信用卡」個人私帳支出 購物 880「耳機」 | 201 | 記一筆成功 |
| `transactions-create-income.json` | `POST /transactions`,「iOS 測試存款」收入 薪資 45000 | 201 | 記一筆成功 |
| `accounts-create-joint-fund.json` | `POST /accounts`,建立活存帳戶「iOS 家庭共同基金」(餘額 10000,`is_joint: 1`) | 201 | 家庭共同基金的標記 |
| `transactions-create-card-shared.json` | `POST /transactions`,「iOS 測試信用卡」家庭公帳支出 購物 3000「全家的日用品」 | 201 | 讓欠款公私拆解有家庭公帳的部分 |
| `accounts-list-with-debt-split.json` | `GET /accounts`,上面兩筆之後 | 200 | 信用卡帳戶的 `shared_debt` 3000、`personal_debt` 16380;家庭共同基金的 `is_joint: 1` |
| `accounts-pay-credit-card.json` | `POST /accounts/pay-credit-card`,從家庭共同基金繳「iOS 測試信用卡」的家庭公帳部分 3000 | 200 | 先沖已出帳待繳款(12000 → 9000),未出帳款不變;產生一筆「信用卡還款」收支明細 |
| `accounts-pay-credit-card-over.json` | 同上，金額 9999999 | 400 | 「繳款金額不可超過當前待繳總額 NT$ 16,380」原樣傳遞 |
| `accounts-pay-credit-card-missing.json` | 同上，沒有 `bank_account_id` | 400 | 「請填寫扣款帳戶、信用卡及正確繳費金額」原樣傳遞 |
| `accounts-rollover-statement.json` | `POST /accounts/:id/rollover-statement`,「iOS 測試小額卡」(未出帳 5000)。2026-10-01 重錄，後端 `97f4789` | 200 | 未出帳 5000 移到已出帳待繳款(8000 → 13000);訊息在 `data.message`,是「帳單出帳作業完成！已轉入已出帳待繳款。」,原樣傳遞 |
| `accounts-rollover-statement-none.json` | 再做一次出帳作業。2026-10-01 重錄，後端 `97f4789` | 400 | 「目前無未出帳金額需出帳」原樣傳遞 |
| `transactions-recent.json` | `GET /transactions?scope=all&limit=6&offset=0`,不帶 `from` / `to`(總覽的最近 6 筆) | 200 | 不限日期，由新到舊 |
| `transactions-list.json` | `GET /transactions?from=2026-09-01&to=2026-09-30&scope=all&limit=200&offset=0` | 200 | `is_shared` 0/1、`account_name`、`user_name`;日期由新到舊 |
| `transactions-account-filter.json` | `GET /transactions?scope=all&limit=200&offset=0&from=2026-01-01&to=2026-12-31&account_id=<iOS 測試存款>`(上游 ADR 0019) | 200 | 只回這個帳戶的 2 筆(`account_id` 都是存款帳戶) |
| `transactions-create-deferred.json` | `POST /transactions` 在「iOS 測試小額卡」記一筆 `defer_to_next_statement: 1`(上游 ADR 0020,錄完刪除) | 201 | 回應帶 `is_billed: 0`、`defer_to_next_statement: 1` |
| `transactions-card-billing-state.json` | `GET /transactions?…&account_id=<小額卡>`,卡上有兩筆:一筆延至下期、一筆日期在上期結帳日之前(後端建立時自動標成已出帳)(錄完都已刪除，卡的餘額還原) | 200 | 延至下期的 `is_billed: 0, defer_to_next_statement: 1`;已出帳的 `is_billed: 1` |
| `transactions-create-missing-fields.json` | `POST /transactions`,沒有 `account_id` | 400 | 「請填寫必填欄位」原樣傳遞 |
| `transactions-update.json` | `PUT /transactions/:id`,用暫時記的一筆(改成 75 元、個人私帳),錄完就刪掉 | 200 | 編輯成功 |
| `transactions-delete.json` | `DELETE /transactions/:id`,刪除上面那筆 | 200 | `{success, data: null}` 視為成功 |
| `transactions-delete-not-found.json` | 再刪一次同一個 id | 404 | 「紀錄不存在」原樣傳遞 |
| `export-transactions.csv` | `GET /export/csv?from=2026-09-01&to=2026-09-30` | 200,`text/csv` | UTF-8 加 BOM 的 CSV 原樣回傳(不是 JSON envelope) |
| `recurring-create-rent.json` | `POST /recurring`,週期支出「房租」12000,每月 5 號，關聯「iOS 測試存款」 | 201 | 新增成功 |
| `recurring-create-insurance.json` | `POST /recurring`,週期支出「年繳保費」24000,每年 15 號，不指定關聯帳戶 | 201 | `account_id` 是 `null` |
| `recurring-create-salary.json` | `POST /recurring`,週期收入「薪水」45000,每月 25 號，關聯「iOS 測試存款」 | 201 | 新增成功 |
| `recurring-create-missing-name.json` | `POST /recurring`,沒有 `name` | 400 | 「請填寫所有必填欄位」原樣傳遞 |
| `recurring-list.json` | `GET /recurring`,上面三項建立之後 | 200 | snake_case;`account_id` 可以是 `null`;JOIN 的 `account_name` |
| `recurring-amortize.json` | `GET /recurring/amortize`,同上 | 200 | 後端算好的 `monthly_expense` 14000、`monthly_income` 45000 |
| `recurring-update.json` | `PUT /recurring/:id`,用暫時建立的項目(改成每半年 20 號 360),錄完就刪掉 | 200 | 編輯成功(回傳更新後的資料列) |
| `recurring-delete.json` | `DELETE /recurring/:id`,刪除上面那個暫時項目 | 200 | `{success, data: null}` 視為成功 |
| `recurring-delete-not-found.json` | 再刪一次同一個 id | 404 | 「項目不存在」原樣傳遞 |
| `recurring-create-quarterly.json` | `POST /recurring`,週期支出「iOS 測試保險費」3000,每季 5 號、`month_of_cycle` 2 | 201 | 回傳 `month_of_cycle`(上游 `feabed3`) |
| `recurring-list-with-month.json` | `GET /recurring`,上面那項存在時 | 200 | 每項都帶 `month_of_cycle`;舊項目是 `1` |
| `recurring-update-month.json` | `PUT /recurring/:id`,把上面那項改成每半年、`month_of_cycle` 4 | 200 | 回傳更新後的 `month_of_cycle` |
| `recurring-delete-quarterly.json` | `DELETE /recurring/:id`,刪除上面那個暫時項目 | 200 | `{success, data: null}` |
| `recurring-list-scope-all.json` | `GET /recurring?scope=all`(上游 ADR 0016 起) | 200 | 多了 `is_shared`(0/1)、`account_is_joint`、`user_name`;全部 = 我建立的加上家人的家庭公帳 |
| `recurring-list-scope-household.json` | `GET /recurring?scope=household` | 200 | 測試帳號沒有家庭公帳項目,回空陣列 |
| `recurring-list-scope-personal.json` | `GET /recurring?scope=personal` | 200 | 我建立的個人私帳項目 |
| `recurring-amortize-scope-all.json` | `GET /recurring/amortize?scope=all` | 200 | 除了 `monthly_expense`、`monthly_income`,後端也回 `items`(iOS 不解碼) |
| `recurring-amortize-scope-household.json` | `GET /recurring/amortize?scope=household` | 200 | 兩個合計都是 0 |
| `forecast-scope-all.json` | `GET /forecast?scope=all`(上游 ADR 0016、0017 起) | 200 | 含「💳 繳卡費 · 卡名」事件(信用卡繳款日,金額是該視角應負擔的已出帳待繳款);`minDate` 永遠有值 |
| `forecast-scope-household.json` | `GET /forecast?scope=household` | 200 | 測試帳號不在任何家庭:起始餘額 6900、沒有事件、最低餘額發生在第一天 |
| `forecast-scope-personal.json` | `GET /forecast?scope=personal` | 200 | 個人私帳:自己的帳戶與項目 |
| `forecast-scope-all-settled.json` | 先 `POST /forecast/settle` 把「房租」(`recurring:<id>:<日期>`)標成已繳，再 `GET /forecast?scope=all`(錄完已還原) | 200 | 房租 `is_settled: true`、仍在事件清單，最低餘額 61,570 → 73,570(後端把已繳的 12,000 排除);其他事件 `is_settled: false`、`can_settle: true` |
| `forecast-settle-on.json` | `POST /forecast/settle {event_key, settled:true}`(上游 ADR 0018) | 200 | `{event_key, is_settled:true}` |
| `forecast-settle-off.json` | 同上 `settled:false` | 200 | `{event_key, is_settled:false}` |
| `forecast-settle-invalid.json` | 同上少了 `event_key` | 400 | 「缺少 event_key」原樣傳遞 |
| `forecast-purchase-scope-household.json` | `POST /forecast/purchase-check {amount:10000, scope:household}` | 200 | 不建議購買、`affectedGoals` 空(公帳視角不檢核個人儲蓄目標) |
| `forecast-purchase-scope-personal.json` | `POST /forecast/purchase-check {amount:10000, scope:personal}` | 200 | 放心購買、`affectedGoals` 帶出儲蓄目標 |
| `recurring-create-shared.json` | `POST /recurring`,週期支出「iOS 測試網路費」899,`is_shared: 1` | 201 | 回傳 `is_shared`、`user_name`(上游 ADR 0016) |
| `recurring-update-ownership.json` | `PUT /recurring/:id`,把上面那項改成 `is_shared: 0` | 200 | 回傳更新後的 `is_shared` |
| `recurring-delete-shared.json` | `DELETE /recurring/:id`,刪除上面那個暫時項目 | 200 | `{success, data: null}` |
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
| `budgets-list-empty.json` | `GET /budgets?month=2026-09`,還沒有任何預算額度時 | 200 | 空清單 |
| `budgets-put-create.json` | `PUT /budgets`,餐飲 5000(新增) | 200 | 回傳設定後的資料列 |
| `budgets-put-update.json` | `PUT /budgets`,餐飲改成 100(同分類同月份會調整原本那筆) | 200 | 同一個 `id` |
| `budgets-put-missing-amount.json` | `PUT /budgets`,沒有 `amount` | 400 | 「請填寫所有欄位」原樣傳遞 |
| `budgets-list.json` | `GET /budgets?month=2026-09`,餐飲 100、購物 1000 設定之後 | 200 | 後端算好的 `spent` 與 `over`(餐飲超支、購物 88%)。預算額度無法刪除，會留在測試帳號的 2026-09 |
| `forecast.json` | `GET /forecast`,台灣時間 2026-09-28 早上錄的 | 200 | camelCase;30 天逐日餘額、`minBalance`、`minDate`、`willOverdraft`、預定收支(房租、薪水)。第一天是 2026-09-27,因為當時後端用 UTC 的今天(`bd0507b` 已改用台灣時間) |
| `forecast-purchase-safe.json` | `POST /forecast/purchase-check {amount: 1000}` | 200 | 放心購買;`affectedGoals` 列出所有有每月預留的儲蓄目標，不管評估結果是哪一種 |
| `forecast-purchase-caution.json` | 同上 `{amount: 50000}`。錄之前先把「沖繩旅遊」的每月預留暫時改成 20000,錄完改回 5000 | 200 | 審慎評估(`affectsSavings: true`) |
| `forecast-purchase-danger.json` | 同上 `{amount: 60000}` | 200 | 不建議購買，最低餘額 -6560 |
| `forecast-purchase-invalid.json` | 同上 `{amount: 0}` | 400 | 「請輸入有效金額」原樣傳遞 |
| `bot-bindings-empty.json` | `GET /bot/bindings`,測試帳號還沒有機器人綁定時 | 200 | 空清單 |
| `bot-pairing-code.json` | `POST /bot/pairing-code` | 200 | 6 碼大寫英數的綁定驗證碼、`expires_in_seconds: 600` |
| `bot-simulate-missing-text.json` | `POST /bot/test-simulate {text: "", platform: "line"}` | 400 | 「請輸入測試訊息」原樣傳遞 |
| `bot-simulate-expense.json` | 同上 `{text: "午餐 120"}`。**會在測試帳號寫入一筆真的收支明細**(預期的結果) | 200 | `reply` 是機器人的回覆文字 |
| `bot-simulate-query.json` | 同上 `{text: "查帳"}` | 200 | 查帳不寫入任何資料 |
| `bot-bindings.json` | `GET /bot/bindings`,模擬對話之後 | 200 | 後端會自動建立「模擬測試助手」的 LINE 綁定 |
| `bot-unbind.json` | `DELETE /bot/bindings/:id`,解除上面那個綁定;錄完測試帳號回到沒有綁定 | 200 | 只回 `{success, message}` |
| `households-current-none.json` | `GET /households/current`,測試帳號沒有家庭群組時 | 200 | `household: null`、`myRole: null` |
| `households-join-invalid.json` | `POST /households/join {code: "FAM-0000"}`。0 不在後端的邀請碼字元表裡，這組不可能存在，不會誤加入別人的家庭 | 404 | 「邀請碼無效或已過期」原樣傳遞 |
| `households-create-missing-name.json` | `POST /households {name: "  "}` | 400 | 「請輸入家庭名稱」原樣傳遞 |
| `households-create.json` | `POST /households {name: "iOS 測試家庭"}`,測試帳號自己建立 | 201 | 我是家庭管理員 |
| `households-current.json` | `GET /households/current`,上面那個家庭群組 | 200 | 成員名冊：`user_id`、`role`、`joined_at`(UTC 的 `YYYY-MM-DD HH:MM:SS`)、`name`、`email` |
| `households-invite.json` | `POST /households/invite` | 200 | `code` 是 `FAM-XXXX`,`expires_at` 是有毫秒的 ISO 8601 |
| `households-join-already-member.json` | 已經在家庭群組裡時 `POST /households/join` | 400 | 「你已經加入家庭群組，無法重複加入」原樣傳遞 |
| `households-invite-none.json` | 沒有家庭時 `POST /households/invite` | 400 | `{success:false, error}` 原樣傳遞;測試把狀態碼換成 403，驗證權限不足的 403 走同一條路(測試帳號只有自己一人、是家庭管理員，錄不到真正的 403) |
| `households-remove-self.json` | 家庭管理員 `DELETE /households/members/自己` | 400 | 「請使用離開家庭功能」原樣傳遞 |
| `households-leave.json` | `DELETE /households/leave`。測試帳號是唯一的成員，離開後後端會刪掉整個家庭群組 | 200 | 只回 `{success, message}`,沒有 `data` |
| `households-leave-none.json` | 再離開一次 | 400 | 「你未加入任何家庭」原樣傳遞 |

### 對齊上游 `bd0507b`(#43)

以下是 2026-09-28 對 `bd0507b` 的後端錄的。

| fixture | 請求 | HTTP | 用來驗證 |
|---|---|---|---|
| `accounts-create-cash.json` | `POST /accounts`,建立現金「iOS 測試皮夾」(`type: cash`,餘額 1500,個人私帳) | 201 | 建立後的回應 |
| `accounts-list-with-cash.json` | `GET /accounts?scope=all`,上面那個現金建立之後 | 200 | `type: "cash"` 解讀成現金;把它改成不認得的類型時只略過那一個 |
| `accounts-balance-with-cash.json` | `GET /accounts/balance?scope=all`,同上 | 200 | `cashTotal` 1500;`available` 由後端算好，含現金(1500 + 101700 − 24380 − 5000 = 73820) |
| `accounts-list-household.json` | `GET /accounts?scope=household` | 200 | 只回傳歸屬家庭共同基金(`is_joint = 1`)的帳戶:「iOS 家庭共同基金」 |
| `accounts-list-household-card-advance.json` | `GET /accounts?scope=household`(2026-10-03,上游 `4fbf863`),測試帳號的個人信用卡記了一筆公帳支出 777 之後;錄完把交易刪掉，帳號還原 | 200 | 公帳範圍多回自己有家庭代墊欠款的個人信用卡(`shared_debt` 777、`unbilled` 777、沒有 `is_masked`);確認 prod 已部署 ADR 0015。**錄不到他人的脫敏卡**(需要第二個帳號)，`is_masked` 的解碼測試用這份真實回應手改欄位，測試裡有註明 |
| `accounts-balance-household-card-advance.json` | `GET /accounts/balance?scope=household`,同上 | 200 | 私卡的家庭代墊算進信用卡待繳:`ccUnbilled` 777、淨可用餘額 `available` 6123 = 6900 − 777 |
| `accounts-balance-personal.json` | `GET /accounts/balance?scope=personal` | 200 | 不含歸屬家庭共同基金的帳戶：活存帳戶 94700(少了共同基金 7000)、淨可用餘額 66820 |
| `accounts-transfer-atm.json` | `POST /accounts/transfer`,「iOS 測試存款」轉 500 到「iOS 測試皮夾」,日期 2026-09-28,備註「ATM 提款」 | 200 | 訊息在 `data.message`;後端建立兩筆「ATM提款」收支明細 |
| `accounts-transfer-same-account.json` | 同上，轉出與轉入都是「iOS 測試皮夾」 | 400 | 「轉出與轉入帳戶不能相同」原樣傳遞 |
| `accounts-transfer-insufficient.json` | 同上，從「iOS 測試皮夾」轉 999999 | 400 | 「轉出帳戶餘額不足（目前餘額：NT$ 2,000）」原樣傳遞 |
| `transactions-list-with-transfer.json` | `GET /transactions?from=2026-09-28&to=2026-09-28&scope=all&limit=200&offset=0`,上面的 ATM 提款之後 | 200 | 兩筆分類「ATM提款」(一筆支出、一筆收入)是系統分類 |
| `transactions-create-cash-advance.json` | `POST /transactions`,「iOS 測試皮夾」家庭公帳支出 餐飲 250「全家晚餐」 | 201 | 用個人現金付公帳支出(個人現金公帳代墊) |
| `households-advances.json` | `GET /households/advances`。先讓測試帳號自己建立一個只有自己的家庭群組「iOS 測試家庭」,錄完下面三份就離開 | 200 | snake_case;累計代墊 250、已報銷 0、待報銷 250;代墊明細帶扣款帳戶名稱與類型 |
| `households-reimburse.json` | `POST /households/reimburse`,從「iOS 家庭共同基金」撥 100 給自己的「iOS 測試存款」 | 200 | 訊息在 `data.message`;後端建立兩筆「公帳代墊報銷」收支明細 |
| `households-reimburse-not-joint.json` | 同上，撥款帳戶用個人的「iOS 測試存款」 | 400 | 「撥款帳戶必須為家庭共同基金公帳 (公用帳戶)」原樣傳遞 |
| `households-advances-after-reimburse.json` | `GET /households/advances`,上面的報銷之後 | 200 | 已報銷 100、待報銷 150;報銷明細帶收款帳戶名稱 |
| `households-advances-no-household.json` | `GET /households/advances`,離開測試家庭群組之後 | 200 | 沒有家庭群組時是空陣列 |

### 對齊上游 `b5cbe09`(#45)

以下是 2026-09-29 對 `b5cbe09` 的後端錄的。

| fixture | 請求 | HTTP | 用來驗證 |
|---|---|---|---|
| `households-advances-with-receiving.json` | `GET /households/advances`。先讓測試帳號自己建立只有自己的家庭群組「iOS 測試家庭」,錄完就離開 | 200 | 每位成員多 `receiving_accounts`(`id`、`name`、`type`,只有 `bank`、`cash`,不含餘額);測試帳號的「iOS 測試存款」「iOS 測試皮夾」 |
| `accounts-reconcile.json` | `POST /accounts/:id/reconcile`,「iOS 測試信用卡」(結帳日 15 號;9/15 之後沒有消費，未出帳本來就是 0) | 200 | 訊息在 `data.message`,另外有 `unbilled`、`shared_debt`、`personal_debt` |
| `accounts-reconcile-not-card.json` | 同上，帶「iOS 測試存款」的 id | 404 | 「信用卡不存在或無權限」原樣傳遞 |

### 對齊上游 `97f4789`(#98)

以下是 2026-10-01 對 `97f4789` 的後端錄的，用的是測試帳號自己的資料，沒有建立或加入家庭。錄之前先用唯讀的 `GET` 比對現況，只重錄真的變了的:

- 交易列(`GET /transactions`)的每一筆多了 `unbilled_offset`(信用卡還款沖到未出帳款的部分，校準用)。iOS 不解碼、不使用。
- 出帳作業的訊息文字改了:成功是「帳單出帳作業完成！已轉入已出帳待繳款。」,沒有未出帳款是「目前無未出帳金額需出帳」。
- 資產帳戶的資料列多了 `last_rollover_at`(`f32ff6c` 就有，iOS 不解碼)。
- 沒變、不重錄:扣款還款與校準的回應形狀和訊息都沒變;家庭的三則訊息(「家庭群組群組」的疊字)`97f4789` 修掉了，而現有的 fixture 本來就是沒有疊字的文字，所以也不用重錄。

| fixture | 請求 | HTTP | 用來驗證 |
|---|---|---|---|
| `transactions-list-unbilled-offset.json` | `GET /transactions?from=2026-09-01&to=2026-09-30&scope=all&limit=200&offset=0`(唯讀) | 200 | 每筆多 `unbilled_offset`,解讀不受影響;包含 4 筆系統分類(ATM提款、公帳代墊報銷)與 1 筆餐飲 |
| `accounts-rollover-statement.json`、`accounts-rollover-statement-none.json` | 見上面「清單」兩列，已用 `97f4789` 重錄 | 200、400 | 訊息原樣傳遞 |

**錄完的狀態**:「iOS 測試小額卡」做過出帳作業，已出帳待繳款 13000、未出帳 0。測試帳號沒有家庭，也沒有留下暫時資料。

### 對齊上游 `f32ff6c`(#54)

`da82a11` 和 `f32ff6c` 沒有新增或變更 fixture。回應的形狀沒變，只有資產帳戶的資料列多了 `last_rollover_at`(上一次結帳日出帳作業的時間),iOS 不解碼，所以不重錄。

後端有幾則訊息的文字改了，例如「紀錄不存在」改成「交易記錄不存在」。上面各表引用的是錄製當時的原文;iOS 原樣顯示後端的訊息，不依文字判斷。出帳作業的兩則訊息在 `97f4789` 又改了，已重錄(見上一節)。

### 從缺:`auth-register-success.json`

2026-09-28 用 `POST /auth/register` 註冊測試帳號時，當時的腳本沒有先建立 `Fixtures/` 目錄，後端回了成功(429 bytes),回應卻沒寫進檔案。註冊同一個 email 只能成功一次，之後只會回 409「此 Email 已被使用」。腳本已經修正成先確認寫得進檔案再打 API。

要補錄註冊成功的回應，得再註冊一個專用 email,需要維護者同意。在那之前，註冊成功的解碼測試沿用 `auth-login-success.json`:後端 `/auth/register` 與 `/auth/login` 回傳的 `data` 形狀相同(`{token, user: {id, email, name}}`)。

### 從缺:加入家庭成功、移除成員成功

兩者都需要第二個帳號:加入得有別人的邀請碼，移除得有另一位一般成員。測試帳號只能加入自己建立的測試家庭，註冊第二個帳號需要維護者同意，所以沒有錄。

- `POST /households/join` 成功時，iOS 只看 `success`,不讀 `data`。
- `DELETE /households/members/:userId` 成功時回 `{success, message}`,形狀跟 `households-leave.json` 一樣。
