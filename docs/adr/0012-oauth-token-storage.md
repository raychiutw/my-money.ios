---
status: accepted
---

# 登入改用上游 OAuth 2.1:存取權杖只放記憶體、更新權杖存 Keychain

上游在 `c899f01` 之前改成 OAuth 2.1 授權伺服器(上游 ADR 0038):登入與註冊在 Worker 的登入頁完成,client 拿到 15 分鐘的存取權杖與會輪替的更新權杖(閒置 30 天失效)。舊的 `/auth/login`、`/auth/register` 是相容模式,上游隨時會關。iOS 必須跟著換,這是之後 DPoP(#337)、帳號安全(#338)、passkey(#339)的前提(#332、#334)。

## Decision

- **登入與註冊都開系統的安全登入視窗**(`ASWebAuthenticationSession`,`prefersEphemeralWebBrowserSession = true`)載入上游的 `/oauth/authorize`,授權碼 + PKCE(`S256`)、比對 `state`;client `ios` 與 redirect URI `com.raychiu.mymoney:/oauth/callback` 是上游寫死的。app 不再接觸密碼,原生的帳密表單與註冊頁移除。「瀏覽器授權」是 Domain 的 seam(`BrowserAuthorizer`),App 層實作,測試用假物件;UI 測試(`-uiTesting`)的登入鈕直接以範例帳號登入。
- **存取權杖只放記憶體;更新權杖與顯示用的使用者資料存 Keychain**(`WhenUnlockedThisDeviceOnly`:只限這支裝置、不進備份)。使用者資料從存取權杖的 JWT payload(`sub`、`email`、`name`)取得,只用於顯示,不驗章(後端驗)。
- `Session` 是「使用者 + 權杖(`SessionTokens`)」的持有者:冷啟動讀回時沒有存取權杖,由更新權杖換新(#335);refresh 輪替後整份 `Session` 重新存一次。畫面 model 只看 `user`。
- **登出**:先清掉本機,再 `POST /oauth/revoke`(帶更新權杖);撤銷失敗也一樣已經登出。
- **舊版權杖遷移**:Keychain 裡解不出更新權杖的舊格式一律清掉、回登入頁重新登入一次(上游不提供把舊版權杖換成新工作階段的端點)。
- OAuth 端點的格式(form-urlencoded、`{access_token, …}`、`{error, error_description}`,都不是 `{success, data}` envelope)只在 `MyMoneyAPI` 處理。

## Consequences

- 這張單獨上線時,存取權杖 15 分鐘後過期就會被登出,也無法在冷啟動恢復登入:必須與 #335(更新權杖輪替與自動續期)一起發佈。
- 「Face ID 登入」(把密碼存 Keychain)失去用途,登入頁與「我的」的開關一併移除;刪除裝置上已存的帳密與相關文件由 #336 處理。
- 每台裝置都是後端的一個登入工作階段,User-Agent 帶 `MyMoney-iOS (iPhone|iPad)`,後端據此顯示裝置名稱。
