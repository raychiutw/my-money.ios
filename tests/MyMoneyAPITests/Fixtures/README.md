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

### 從缺:`auth-register-success.json`

2026-09-28 用 `POST /auth/register` 註冊測試帳號時，當時的腳本沒有先建立 `Fixtures/` 目錄，後端回了成功(429 bytes),回應卻沒寫進檔案。註冊同一個 email 只能成功一次，之後只會回 409「此 Email 已被使用」。腳本已經修正成先確認寫得進檔案再打 API。

要補錄註冊成功的回應，得再註冊一個專用 email,需要維護者同意。在那之前，註冊成功的解碼測試沿用 `auth-login-success.json`:後端 `/auth/register` 與 `/auth/login` 回傳的 `data` 形狀相同(`{token, user: {id, email, name}}`)。
