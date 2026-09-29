# TestFlight 發佈

「我的記帳本」只透過 TestFlight 內部測試發給家人，不上 App Store(ADR-0001)。上傳由 GitHub Actions 的 `TestFlight` workflow(`.github/workflows/testflight.yml`)負責，做法參照 raychiutw/vocaby。

## 發一版

**PR 合併進 `master` 就會自動上傳**。只改 `docs/` 或 `.md` 的合併不會上傳。要手動重發(例如 build 快到 90 天期限):

```bash
gh workflow run testflight.yml --ref master
gh run watch "$(gh run list --workflow testflight.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

workflow 會依序做這幾件事:

1. 檢查這個 commit 是不是 PR 的 merge commit,而且那個 PR 的 CI 成功過(`check` job,跑在 ubuntu,幾秒鐘)。
   是的話跳過測試，同一份程式碼不測兩次;不是的話(直接 push、手動觸發在沒跑過 CI 的 commit 上)先跑整套 CI(`ci.yml`)。
2. 在 `xcode-27` runner 上 archive,並以自動簽章 export 後上傳。
3. 輪詢 App Store Connect,等 build 可供內部測試才結束(`scripts/wait-for-testflight.rb`,最多 30 分鐘)。

合併之後大約 6～8 分鐘就能在 TestFlight 安裝。以前要手動觸發，而且 master 的 CI 和 TestFlight 會各自把 PR 已經測過的測試再跑一次，要 60 分鐘以上。

只有 `master` 會上傳，`testflight` environment 也只允許 `master` 部署。

已知限制：沒有比對 PR 測試當時的 `master`。兩個 PR 接連合併時，後合併的那個沒測過合併後的組合;要嚴格就改成要求 PR 合併前先更新到最新的 `master`。

## CI

- 只在 PR 上跑(`ci.yml`),`master` 不另外跑。
- UI 測試的 runner 偶爾在開始跑測試之前就當掉(`never finished bootstrapping`),跟程式碼無關。
  遇到這種情況，CI 不重新編譯，用 `test-without-building` 自動重跑一次;其他失敗照常算失敗。

## 版本號與 build 號

- **版本號**(`CFBundleShortVersionString`):專案 build settings 的 `MARKETING_VERSION`,app target 和 UI 測試 target 的 Debug、Release 共 4 處，要一起改。
  - 格式必須是三段整數 `[Major].[Minor].[Patch]`([Apple 文件](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring))。
  - 正式版之前用 `0.y.z`,從 `0.1.0` 開始。
  - **每次發佈到 TestFlight 都要遞增版號**,不要用同一個版號重複發佈:加功能遞增 minor(`0.1.0` → `0.2.0`),只修 bug 遞增 patch(`0.1.0` → `0.1.1`)。
  - 上傳只發生在合併進 master 時，所以遞增版號的 commit 要包在要合併的那個 PR 裡;手動重發(`workflow_dispatch`)前也要先確認版號已經遞增。
  - 正式版才到 `1.0.0`。
- **build 號**(`CFBundleVersion`):上傳時用 `GITHUB_RUN_ID` 覆寫。它全域唯一又遞增，所以每次發佈都會自動更新，不用手動改。專案裡的 `CURRENT_PROJECT_VERSION = 1` 只給本機建置用。

## 內部測試者

內部測試者必須是 App Store Connect 使用者，最多 100 人。

1. 在「使用者與存取權限」邀請家人，Apple Account email 由使用者提供。
   - 角色用「**行銷**」。實測「客戶支援」不會出現在內部測試員名單，改成「行銷」後才選得到。
   - App 存取要勾「我的記帳本」。
2. 在 App 的 TestFlight 頁，把家人加進內部測試群組「家人」。這個群組已經開啟自動分發，新 build 上傳後會自動發給群組裡的人。
3. 家人用 TestFlight app 接受邀請後安裝。

**每個 build 只能安裝 90 天**,到期前要再發一版。

## 一次性設定

第一次發佈前做一次，換 key 或重建時再照做。

- **App ID**:`com.raychiu.mymoney`。自動簽章第一次 archive 時會註冊。App Store Connect「新增 App」表單只能選已註冊的 App ID,所以要先註冊：在 Certificates, Identifiers & Profiles 手動註冊，或先 archive 一次。
- **App Store Connect app 紀錄**:
  - 名稱「我的記帳本」,主要語言繁體中文。
  - bundle ID `com.raychiu.mymoney`,SKU `mymoney-ios-20260928`(建立後不能改)。
- **簽章**:
  - 自動簽章，Distribution 憑證由 Apple 雲端管理。
  - 建立雲端管理的 Distribution 憑證只有 Account Holder 或 Admin 能做，所以 API key 要用 **Admin** 角色的 team key。
  - 目前和 vocaby 共用「Vocaby GitHub Admin」這把 key。
- **GitHub environment `testflight`**:
  - 部署分支限定 `master`。
  - 變數 `APPLE_TEAM_ID`。
  - secret `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY`(`.p8` 的內容)。
  - `.p8` 只存在本機和 GitHub secret,不進 repo。

  ```bash
  gh variable set APPLE_TEAM_ID --env testflight --body '<Team ID>'
  gh secret set ASC_KEY_ID --env testflight
  gh secret set ASC_ISSUER_ID --env testflight
  gh secret set ASC_PRIVATE_KEY --env testflight < <.p8 路徑>
  ```

- **加密出口合規**:`ITSAppUsesNonExemptEncryption = NO`(只用 HTTPS),上傳後不必再回答出口合規問題。
- **只限內部測試**:`.github/ExportOptions.plist` 設了 `testFlightInternalTestingOnly`,上傳的 build 不能拿去外部測試或送審。
