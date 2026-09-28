# TestFlight 發佈

「我的記帳本」只透過 TestFlight 內部測試發給家人，不上 App Store(ADR-0001)。上傳由 GitHub Actions 的 `TestFlight` workflow(`.github/workflows/testflight.yml`)手動觸發，做法參照 raychiutw/vocaby。

## 發一版

```bash
gh workflow run testflight.yml --ref master
gh run watch "$(gh run list --workflow testflight.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

workflow 會依序做這幾件事:

1. 重跑整套 CI(`ci.yml`)。
2. 在 `xcode-27` runner 上 archive,並以自動簽章 export 後上傳。
3. 輪詢 App Store Connect,等 build 可供內部測試才結束(`scripts/wait-for-testflight.rb`,最多 30 分鐘)。

只有 `master` 會上傳：其他分支觸發時只跑測試。`testflight` environment 也只允許 `master` 部署。

## 版本號與 build 號

- **版本號**(`CFBundleShortVersionString`):專案 build settings 的 `MARKETING_VERSION`,要發新版時手動改。
- **build 號**(`CFBundleVersion`):上傳時用 `GITHUB_RUN_ID` 覆寫。它全域唯一又遞增，所以同一個版本號可以重複上傳。專案裡的 `CURRENT_PROJECT_VERSION = 1` 只給本機建置用。

## 內部測試者

內部測試者必須是 App Store Connect 使用者，最多 100 人。

1. 在「使用者與存取權限」邀請家人，Apple Account email 由使用者提供。角色選權限最小的，App 存取只勾「我的記帳本」。如果在 TestFlight 內部群組找不到這個人，依 Apple 文件改他的角色。
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
