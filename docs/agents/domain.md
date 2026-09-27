# Domain docs

本文件定義 engineering skill 探索 codebase 時，應該怎麼使用本 repo 的 domain 文件。

## 探索前先讀

- 根目錄的 `CONTEXT.md`(詞彙表)
- `docs/adr/` 中跟目前工作相關的 ADR
- 跟 web 功能有關的工作，還要讀 `docs/parity.md`

## 檔案結構

本 repo 採 single-context:根目錄一份 `CONTEXT.md`,決策放在 `docs/adr/`。`CONTEXT.md` 只定義詞彙，不寫實作細節。web(`onion523/my-money`)日後若建立自己的 `CONTEXT.md`,改以它為 source of truth,本 repo 跟著調整。

## 使用詞彙表的詞

issue 標題、重構提案、hypothesis、測試名稱和 UI 文字，都要使用 `CONTEXT.md` 定義的詞，不可改用詞彙表列在「避免」裡的同義詞。需要的概念還不在詞彙表裡時，交給 `/domain-modeling` 補上。

## 標示跟 ADR 衝突的地方

產出跟既有 ADR 衝突時，必須明確指出，不可以默默覆蓋：

> 與 ADR-0001 衝突;但因為……,值得重新檢討。
