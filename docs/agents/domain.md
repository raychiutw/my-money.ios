# Domain docs

本文件定義 engineering skill 探索 codebase 時，應該怎麼使用本 repo 的 domain 文件。

## 探索前先讀

- 根目錄的 **`GLOSSARY.md`**(詞彙表)
- **`docs/adr/`** 中跟目前工作相關的 ADR
- 跟 web 功能有關的工作，還要讀 `docs/parity.md`

## 檔案結構

本 repo 採 single-context(沒有 `GLOSSARY-MAP.md`):根目錄一份 `GLOSSARY.md`,決策放在 `docs/adr/`。

```
/
├── GLOSSARY.md
├── docs/adr/
└── src/
```

`GLOSSARY.md` 只定義詞彙，不寫實作細節。它的 source of truth 是上游 web(`onion523/my-money`)的 `CONTEXT.md`(上游仍用舊檔名):上游有定義的概念照用上游正名，iOS 只補上游沒有的詞與刻意的本地例外，規則寫在 `GLOSSARY.md` 開頭。

## 使用詞彙表的詞

issue 標題、重構提案、hypothesis、測試名稱和 UI 文字，都要使用 `GLOSSARY.md` 定義的詞，不可改用詞彙表列在「_避免_」裡的同義詞。需要的概念還不在詞彙表裡時，可能是自創了專案不用的說法(重新考慮),也可能是真的缺詞(交給 `/domain-modeling` 補上)。

## 標示跟 ADR 衝突的地方

產出跟既有 ADR 衝突時，必須明確指出，不可以默默覆蓋：

> 與 ADR-0001 衝突;但因為……,值得重新檢討。
