---
status: accepted
---

# 登入改用上游 OAuth 2.1:存取權杖只放記憶體、更新權杖存 Keychain

上游在 `c899f01` 之前改成 OAuth 2.1 授權伺服器(上游 ADR 0038):登入與註冊在 Worker 的登入頁完成,client 拿到 15 分鐘的存取權杖與會輪替的更新權杖(閒置 30 天失效)。舊的 `/auth/login`、`/auth/register` 是相容模式,上游隨時會關。iOS 必須跟著換,這是之後 DPoP(#337)、帳號安全(#338)、passkey(#339)的前提(#332、#334)。

## Decision

- **登入與註冊都開系統的安全登入視窗**(`ASWebAuthenticationSession`,`prefersEphemeralWebBrowserSession = true`)載入上游的 `/oauth/authorize`,授權碼 + PKCE(`S256`)、比對 `state`;client `ios` 與 redirect URI `com.raychiu.mymoney:/oauth/callback` 是上游寫死的。app 不再接觸密碼,原生的帳密表單與註冊頁移除。「瀏覽器授權」是 Domain 的 seam(`BrowserAuthorizer`),App 層實作,測試用假物件;UI 測試(`-uiTesting`)的登入鈕直接以範例帳號登入。
- **登入頁外觀(#344,上游 ADR 0042)與 Face ID 登入鈕(#353,上游 ADR 0044 `0044-oauth-login-biometric-submit.md`,onion523/my-money#217)**:授權網址多帶兩個純外觀參數。`biometry`:這台有 Face ID／Touch ID／Optic ID 時帶 `faceid`／`touchid`／`opticid`,登入頁才顯示「用 Face ID 登入」按鈕;只有裝置密碼或都沒有就不帶。`font_scale`:Dynamic Type 的 body 字級除以預設 17pt,夾在 1～3.1、最多兩位小數、小數點固定用「.」(不跟語系),大於 1 才帶。兩者由 composition root 在每次開登入視窗時提供(`LoginPageAppearance`)。這個按鈕是帳密表單的第二個送出鈕(#353、#354,`biometric=1` 的來源是上游 ADR 0044):帳密通過後照常導回,多帶 `biometric=1`,登入結果(`SignInResult.biometric`)據此標記為生物辨識登入(#355)。app 沒有原生 passkey 登入。
- **存取權杖只放記憶體;更新權杖與顯示用的使用者資料存 Keychain**(`WhenUnlockedThisDeviceOnly`:只限這支裝置、不進備份)。使用者資料從存取權杖的 JWT payload(`sub`、`email`、`name`)取得,只用於顯示,不驗章(後端驗)。
- **更新權杖的兩種保護等級(Face ID 登入,#357)**:同一時間只存一份,各用一個 Keychain 項目(account `session`／`session.biometric`)。
  - 一般:`WhenUnlockedThisDeviceOnly`。
  - 受生物辨識保護:`WhenPasscodeSetThisDeviceOnly` 加 `SecAccessControl` `.biometryCurrentSet`——只認目前錄好的臉(指紋),**不接受裝置密碼**,新增或更改臉部資料後項目失效;只限這支裝置。寫入與刪除不需要刷臉,只有讀取內容會由系統跳刷臉;讀取在背景執行,不阻塞 main thread,結果分成功／取消／失敗／已失效(`ProtectedSessionLoad`;`errSecItemNotFound` 或內容解不出來算失效,失效時清掉保存與 DPoP 金鑰)。查有沒有存、存哪一種只查屬性、不准跳提示(`LAContext.interactionNotAllowed`)。
  - **綁定**:登入結果是生物辨識登入時直接刷臉(不詢問):先存成受保護的再讀一次,通過就留著;取消或失敗改存一般,照樣登入。
  - **一般登入**(沒帶 `biometric=1`):裝置上有受保護的保存(不論是否登出保留)且是同一個 user id,就換成新的 session、**維持受保護**(寫入不需刷臉,Face ID 登入維持開啟);不同 user id 清掉前一個人的、改存一般(換帳號不會刷臉進到別人的帳號);沒有受保護的保存就存一般。受保護的保存不刷臉讀不出是誰,所以存檔時另存一個一般項目(account `session.owner`,內容是 user id、`WhenUnlockedThisDeviceOnly`),跟保存一起寫入、一起刪除。
  - **冷啟動**:有受保護的保存時先刷臉(這段期間根畫面空白,不顯示登入頁),通過才進 tab 外殼;取消或失敗維持未登入,綁定留著下次再試;已失效就清掉。
  - **刷臉通過後先 refresh(#365,對齊 trip-planner ADR-0020「通過就 refresh 並進首頁」)**:冷啟動與登入入口頁兩條路徑都一樣,刷臉讀出受保護的 session 後先用更新權杖換新一次(`AuthRepository.refreshSession()`,翻譯層沿用 `APIClient` 的 refresh 與單一進行中的 refresh),完成前根畫面維持解鎖中的空白背景、還不進首頁。換新期間 session 還不是目前的(`current` 是 nil),`AppSession` 另外持有這份 session,透過 `SessionProvider` 提供權杖、接收結果:成功存回新權杖(保留原本的保護等級,不刷臉)後進首頁;`invalid_grant`(或本機沒有金鑰的 `invalid_dpop_proof`)清掉保存與「登出後保留」記號、翻譯層刪 DPoP 金鑰,不進首頁、直接開登入網頁;網路錯誤與 5xx 照樣進首頁(離線也能先看到畫面),之後的請求照既有規則處理。
  - **refresh 輪替**:先刪再寫、保留原本的保護等級,不觸發刷臉。刪除帳號、登入工作階段失效、一般保存的人登出都清掉兩種保存。
  - **Face ID 登入的人登出時保留(#364,對齊 trip-planner ADR-0020)**:受保護的保存在登出時**不撤銷**,保存與 DPoP 金鑰都留著(仍只接受生物辨識);一般保存照舊撤銷並清掉。登出後顯示**登入入口頁**(只有品牌與「登入」,只在這個情況出現),冷啟動也停在這頁、不自動刷臉;沒登出、只是關掉 App 的冷啟動照舊自動刷臉,沒有任何保存照舊直接開登入網頁。入口頁按「登入」:有保留就直接刷臉(不另設按鈕、不顯示帳號),通過後先 refresh 再進首頁(#365,見上);刷臉取消或失敗開登入網頁,保留的先不刪;沒有保留就直接開登入網頁。網頁登入成功一律換成新的保存,規則同上面的「一般登入」(同帳號維持受保護,換掉的是憑證、不是保護)。每次登入換新的 DPoP 金鑰,前一個人的金鑰也一併換掉;**換碼成功才取代保存的金鑰**(新金鑰先只在記憶體簽換碼的 proof),換碼失敗或取消時保留的金鑰不動。refresh 被拒(`invalid_grant`)或項目失效照舊清掉、開登入網頁。不加「忘記這支手機」「使用其他帳號」,登出確認框不加說明。刪除帳號照舊全部清除。
    - **「登出後保留」記號存在 Keychain**:同一個 service 下 account `session.kept-after-sign-out` 的項目,內容是登出的人的 user id(`WhenUnlockedThisDeviceOnly`;同帳號判斷改看 `session.owner`,記號只看有沒有),跟保存放一起,重裝 app 時兩者一起留下或一起消失(UserDefaults 重裝會清掉、Keychain 不會,分開放會讓重裝後的冷啟動自動刷臉)。只有保存是受保護的才看記號;`clear()` 一併清掉,存檔不動它;任何 session 開始(刷臉讀出、網頁登入)都清掉。
    - 登出前送出的 refresh 晚回來時,保留的保存換成輪替後的權杖(不刷臉),避免留下已作廢的更新權杖。
    - 登出前送出的請求晚回 401(`invalid_token` 或 `invalid_grant`)不清掉保留的保存與 DPoP 金鑰:翻譯層把請求送出時的更新權杖交給 `sessionDidExpire(refresh:)`,app 只結束目前的 session(更新權杖相符),結束了翻譯層才刪金鑰。
  - 真的刷臉、`.biometryCurrentSet` 在臉部資料變更後回哪個錯誤碼,只能在真機確認。
- `Session` 是「使用者 + 權杖(`SessionTokens`)」的持有者:冷啟動讀回時沒有存取權杖,由更新權杖換新(#335);refresh 輪替後整份 `Session` 重新存一次。畫面 model 只看 `user`。
- **登出**:先清掉本機,再 `POST /oauth/revoke`(帶更新權杖);撤銷失敗也一樣已經登出。Face ID 登入的人例外,不撤銷(見上)。
- **舊版權杖遷移**:Keychain 裡解不出更新權杖的舊格式一律清掉、開登入網頁重新登入一次(上游不提供把舊版權杖換成新工作階段的端點)。
- **自動續期(#335)**:`APIClient` 送出前若沒有存取權杖(冷啟動)或一分鐘內到期,先用 `grant_type=refresh_token` 換新。冷啟動不另設啟動畫面,也不在啟動時主動 refresh:第一個請求送出前才 refresh,第一批請求共用同一次。例外是刷臉讀出受保護的 session(#365,見上):通過後、進首頁前主動 refresh 一次,不管存取權杖是否還有效。同一時間只送一個 refresh(其他請求等同一個結果)。`invalid_grant` 清掉登入狀態;網路錯誤與 5xx 保留更新權杖,原請求照一般錯誤顯示(上游 #208)。refresh 回來時若目前 session 的更新權杖已經不是送出的那個(期間登出又登入),結果不理會,不蓋掉新的 session。
- **DPoP 金鑰(#337,上游 ADR 0039)**:每次登入產生新的 P-256 金鑰,取代舊的;實機放 Secure Enclave(Keychain 只存加密過的參照),模擬器沒有 Secure Enclave 時改存軟體金鑰,存取等級同更新權杖。產生失敗時不綁定、照舊用 `Bearer`(同 web)。換碼、refresh 與每個受保護的請求都帶 proof;`iat` 用依 `invalid_dpop_proof` 回應的 `Date` 校正過的時間。**刪除時機**:登出(撤銷之後;Face ID 登入的人登出時保留,#364)、刪除帳號成功、受保護的保存失效(臉部資料變更),以及所有工作階段失效的路徑(`invalid_grant`、重送仍 `invalid_token`、本機沒有金鑰的 `invalid_dpop_proof`)。
- **401 分類**(依 `WWW-Authenticate`,不看路徑):
  - `invalid_token`:refresh 後重送一次;重送仍 401 才登出。
  - `invalid_dpop_proof`:多半是手機時間不準,依 `Date` 校正、重簽重送一次;仍失敗只顯示錯誤,**不登出**。
  - 例外:refresh 回 `invalid_dpop_proof` 而本機**沒有金鑰**(工作階段已綁定、Secure Enclave 金鑰遺失),再試也不會過,當成 `invalid_grant` 登出。有金鑰時仍照上一條。
  - 沒有 `WWW-Authenticate` 的 401(帳密錯誤、「目前密碼錯誤」):照顯示後端訊息,不登出。
- OAuth 端點的格式(form-urlencoded、`{access_token, …}`、`{error, error_description}`,都不是 `{success, data}` envelope)只在 `MyMoneyAPI` 處理。

## Consequences

- 「Face ID 登入」(把密碼存 Keychain)失去用途,登入頁與「我的」的開關一併移除;刪除裝置上已存的帳密與相關文件由 #336 處理。#353 起以「更新權杖受生物辨識保護」重新提供 Face ID 登入,不再碰密碼。
- Face ID 登入的人登出後,伺服器端的登入工作階段仍有效(最後一次 refresh 後 30 天失效),但綁定這支手機的 DPoP 金鑰,金鑰不在就用不了;可從其他已登入的裝置在「帳號安全」登出它。保留後改用網頁登入時,前一個工作階段不撤銷(同樣 30 天後失效)。共用手機換人時,在刷臉取消後用自己的帳號登入,前一個人的保存與金鑰就被取代;同一個人刷臉取消後改用網頁一般登入,綁定維持。#353 Out of Scope 的「登出一律真的登出」由 #364 取代。
- 每台裝置都是後端的一個登入工作階段,User-Agent 帶 `MyMoney-iOS (iPhone|iPad)`,後端據此顯示裝置名稱。
