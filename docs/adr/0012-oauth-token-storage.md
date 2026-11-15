---
status: accepted
---

# 登入改用上游 OAuth 2.1:存取權杖只放記憶體、更新權杖存 Keychain

上游在 `c899f01` 之前改成 OAuth 2.1 授權伺服器(上游 ADR 0038):登入與註冊在 Worker 的登入頁完成,client 拿到 15 分鐘的存取權杖與會輪替的更新權杖(閒置 30 天失效)。舊的 `/auth/login`、`/auth/register` 是相容模式,上游隨時會關。iOS 必須跟著換,這是之後 DPoP(#337)、帳號安全(#338)、passkey(#339)的前提(#332、#334)。

## Decision

- **登入與註冊都開系統的安全登入視窗**(`ASWebAuthenticationSession`,`prefersEphemeralWebBrowserSession = true`)載入上游的 `/oauth/authorize`,授權碼 + PKCE(`S256`)、比對 `state`;client `ios` 與 redirect URI `com.raychiu.mymoney:/oauth/callback` 是上游寫死的。app 不再接觸密碼,原生的帳密表單與註冊頁移除。「瀏覽器授權」是 Domain 的 seam(`BrowserAuthorizer`),App 層實作,測試用假物件;UI 測試(`-uiTesting`)的登入鈕直接以範例帳號登入。
- **登入頁外觀與切換到 passkey(#344,上游 ADR 0042)**:授權網址多帶兩個純外觀參數。`biometry`:這台有 Face ID／Touch ID／Optic ID 時帶 `faceid`／`touchid`／`opticid`,登入頁才顯示「用 Face ID 登入」;只有裝置密碼或都沒有就不帶。`font_scale`:Dynamic Type 的 body 字級除以預設 17pt,夾在 1～3.1、最多兩位小數、小數點固定用「.」(不跟語系),大於 1 才帶。兩者由 composition root 在每次開登入視窗時提供(`LoginPageAppearance`)。按下「用 Face ID 登入」時 Worker 頁不做 WebAuthn(RP ID 是別的網域),而是導回 `error=passkey_requested`:`state` 相符就關掉登入視窗、直接走原生 passkey 登入(#339),使用者取消一樣留在登入頁、不顯示錯誤;`state` 不符照一般的 state 不符處理。
- **存取權杖只放記憶體;更新權杖與顯示用的使用者資料存 Keychain**(`WhenUnlockedThisDeviceOnly`:只限這支裝置、不進備份)。使用者資料從存取權杖的 JWT payload(`sub`、`email`、`name`)取得,只用於顯示,不驗章(後端驗)。
- `Session` 是「使用者 + 權杖(`SessionTokens`)」的持有者:冷啟動讀回時沒有存取權杖,由更新權杖換新(#335);refresh 輪替後整份 `Session` 重新存一次。畫面 model 只看 `user`。
- **登出**:先清掉本機,再 `POST /oauth/revoke`(帶更新權杖);撤銷失敗也一樣已經登出。
- **舊版權杖遷移**:Keychain 裡解不出更新權杖的舊格式一律清掉、回登入頁重新登入一次(上游不提供把舊版權杖換成新工作階段的端點)。
- **自動續期(#335)**:`APIClient` 送出前若沒有存取權杖(冷啟動)或一分鐘內到期,先用 `grant_type=refresh_token` 換新。冷啟動不另設啟動畫面,也不在啟動時主動 refresh:第一個請求送出前才 refresh,第一批請求共用同一次。同一時間只送一個 refresh(其他請求等同一個結果)。`invalid_grant` 清掉登入狀態;網路錯誤與 5xx 保留更新權杖,原請求照一般錯誤顯示(上游 #208)。refresh 回來時若目前 session 的更新權杖已經不是送出的那個(期間登出又登入),結果不理會,不蓋掉新的 session。
- **DPoP 金鑰(#337,上游 ADR 0039)**:每次登入(帳密或 passkey)產生新的 P-256 金鑰,取代舊的;實機放 Secure Enclave(Keychain 只存加密過的參照),模擬器沒有 Secure Enclave 時改存軟體金鑰,存取等級同更新權杖。產生失敗時不綁定、照舊用 `Bearer`(同 web)。換碼、refresh 與每個受保護的請求都帶 proof;`iat` 用依 `invalid_dpop_proof` 回應的 `Date` 校正過的時間。**刪除時機**:登出(撤銷之後)、刪除帳號成功,以及所有工作階段失效的路徑(`invalid_grant`、重送仍 `invalid_token`、本機沒有金鑰的 `invalid_dpop_proof`)。
- **401 分類**(依 `WWW-Authenticate`,不看路徑):
  - `invalid_token`:refresh 後重送一次;重送仍 401 才登出。
  - `invalid_dpop_proof`:多半是手機時間不準,依 `Date` 校正、重簽重送一次;仍失敗只顯示錯誤,**不登出**。
  - 例外:refresh 回 `invalid_dpop_proof` 而本機**沒有金鑰**(工作階段已綁定、Secure Enclave 金鑰遺失),再試也不會過,當成 `invalid_grant` 登出。有金鑰時仍照上一條。
  - 沒有 `WWW-Authenticate` 的 401(帳密錯誤、passkey 驗證失敗、「目前密碼錯誤」):照顯示後端訊息,不登出。
- OAuth 端點的格式(form-urlencoded、`{access_token, …}`、`{error, error_description}`,都不是 `{success, data}` envelope)只在 `MyMoneyAPI` 處理。

## Consequences

- 「Face ID 登入」(把密碼存 Keychain)失去用途,登入頁與「我的」的開關一併移除;刪除裝置上已存的帳密與相關文件由 #336 處理。
- 每台裝置都是後端的一個登入工作階段,User-Agent 帶 `MyMoney-iOS (iPhone|iPad)`,後端據此顯示裝置名稱。
