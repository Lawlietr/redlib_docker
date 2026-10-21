# TODO

> 本檔只放**工作進度與優先級**。每個項目 = 做什麼 + 為什麼/範圍 + 優先級，並連結到 `design/` 的實作指引。
> 詳細說明、踩坑、部署步驟一律放 `design/`，不在這裡重複。
> 本專案的 CI：本地 Forgejo（多架構發佈）+ GitHub Actions（amd64 編譯、ghcr 鏡像）。

## 優先級定義

| 級 | 含義 |
|----|------|
| **P0** | 緊急且重要：阻塞部署/上線、影響正確性或穩定性，需立即處理 |
| **P1** | 重要不緊急：影響可靠性/可觀測性/品質，近期要推但非阻塞 |
| **P2** | 有价值但可排後：改善體驗、重構、非阻塞的補齊 |
| **P3** | 想法/可選：nice-to-have、長期評估項 |

## 維護慣例
- 完成項移到「近期完成」並標日期；**待辦一律放上方對應優先級**，不要只寫在「近期完成」的敘述裡。
- 新增待辦時直接開新條目（優先級由你指定或先問）。
- 每條待辦保持「做什麼 + 為什麼/範圍 + 優先級 + design 連結」四要素，細節不展開。

## P2 — 鄰居故障：首頁與人機驗證（不在 #592 範圍）
- **做什麼**：另外單獨評估「首頁 feed 的 parse error」與「Anubis PoW 擋程式化存取」兩條上游 issue 對應的 PR。
- **為什麼**：貼文路由的修正明確標示不處理這兩條；若不另立條目會誤以為一併修好。
- **優先級**：P2（本機實測這兩個端點目前仍正常，先觀望）。
- 細節：`design/error-triage-playbook.md` §7 末段。

## P1 — 上游未合併 PR 的 bake 鏈（Tier 1）
- **做什麼**：把 6 支仍未 upstream 合併的上游 PR（#549/#542/#521/#560/#539/#592）bake 進建置來源；清單放 `redlib-prs.txt`（單一來源），套用邏輯放 `.build/apply_redlib_prs.sh`，由 `Dockerfile` 與 `.forgejo/scripts/build_and_push.sh` 共用。
- **為什麼**：2026-09-18「已全部併入 upstream main」的判斷錯誤（引用的 commit 是我們 build 內的本地 merge tip），upstream main 至今沒有這些改動 → 現行發佈映像少了 CMAF/rich:video 影片、預設 post sort 生效、lazy-load、分享連結、0 則留言 panic 修正。
- **狀態**：本輪已完成 —— 文件更正、bake 鏈接回兩條 build 路徑、本地 x86-64 編譯驗證、GitHub Actions 編譯驗證。
- **優先級**：P1（已修掉功能缺口，但含一處 breaking 行為需線上確認）。
- 細節：`design/upstream-pr-bake.md`（§2 清單、§5 漂移重做、§7 驗證、§8 風險）。

## P1 — bake 上線後的功能回歸
- **做什麼**：部署新映像後照 checklist 逐項確認（影片 proxy 新格式、0 則留言 permalink、預設 post sort 對新訪客生效、`/u/<user>/s/<id>` 分享連結、圖片 lazy-load），並確認舊影片 proxy 連結 404 的影響可接受。
- **為什麼**：五支 PR 都是 clean merge 且不動依賴，但 clean merge ≠ 語意正確；其中影片 proxy 路徑變更是 breaking。
- **優先級**：P1。
- 細節：`design/upstream-pr-bake.md` §7、§8。

## P2 — Tier 2 上游 PR 的取捨（需決策）
- **做什麼**：逐支決定是否加入 `redlib-prs.txt`：#572（RSS 媒體，取代 #563）、#568（footer 原始碼連結）、#566（geo filter）、#577（Tor onion 入口）、#564（每頁文章數，上游 WIP）、#578（Markdown 回應）。
- **為什麼**：都對現行 main clean-merge；但 #566/#564/#568 會新增 runtime env（需同步 `.env.example` 與 AGENTS.md 變數表），#577 與先前「不採用 fork 的 Tor」決策同類、需明確翻案。
- **優先級**：P2（有价值、可排後；先要決策再動 build）。
- 細節：`design/upstream-pr-bake.md` §3、§4。

## P3 — GitHub Actions 產 arm64（對稱到 ghcr）
- **做什麼**：讓 GitHub 端也能產 arm64（目前只 amd64），或改用與本地 Forgejo 相同的 musl 交叉編譯路徑。
- **為什麼**：目前 ghcr 鏡像只有 amd64；多架構只由本地 runner 發佈。三條可行路（交叉工具鏈 / QEMU buildx / arm64 hosted runner）的取捨已記錄。
- **優先級**：P3。
- 細節：`design/github-actions-workflow.md` §5、`design/multi-arch-build.md` §11。

## 近期完成
- 2026-10-21：**雙架構上線確認** —— amd64 與 arm64 的 redlib container 都已架起來，實測兩個架構都正常運行（跑的是含 #592 的六支 bake 映像）。逐功能線上核對（影片 proxy、panic、post sort、分享連結、lazy-load）仍未做，保留在上方 P1 條目。
- 2026-10-21：**bake 上游 #592 修好貼文頁**（Reddit 對匿名 client 的路徑規則封鎖 → 前端 parse error）。六支 Tier 1 累積 `--no-ff` 全 clean；本地雙映像 A/B 實測（對照組精確重現舊錯誤、含 592 組 200 + 留言正常 + 回歸清單全過）；`redlib-prs.txt` 加行、`upstream-pr-bake.md` §2/§7/§8 同步（§8.8 記錄**繞行**屬性、再壞的觸發條件與 observable 字串）；新增 `RELEASE_NOTES.md`（英文）說明這只是暫緩之計而非真正修正，README 雙語加指針與警告。
- 2026-10-21：**新增 `design/error-triage-playbook.md`** —— 從「貼文頁 parse error」事件沉澱出可重現的溯源 SOP：錯誤訊息→呼叫點映射、上游 PR 基底檢查、**含/不含候選 PR 的雙映像端到端 A/B**（取代裸 curl 探測，後者在無合法 token 時會給假陰性）、固定回歸清單（含負 control 要回正確 404 而非 parse error）、tier 判定與記帳要求（繞行 vs 根治、observable 字串）。
- 2026-10-07：**更正 9/18 的 bake 退役判斷**（上游 main 未含那 5 支 PR）；重新接回 bake 鏈，改用上游 PR 取代原 fork port 計畫的 C/D1 子集；新增 `redlib-prs.txt` + `.build/apply_redlib_prs.sh` 供 `Dockerfile` 與多架構腳本共用；兩條 workflow 的觸發路徑補上清單與 `.build/**`；新增 `design/upstream-pr-bake.md`。
- 2026-10-07：**GitHub 遠端上線**（`github.com/Lawlietr/redlib_docker`，private），push 觸發 `.github/workflows/build.yml` 在 `ubuntu-latest` 原生編 amd64 並推 `ghcr.io/lawlietr/redlib:latest`；workflow 補 `packages: write`（首次建立 ghcr package 所需）。文件：`design/github-actions-workflow.md` 全面更新（含與 `.forgejo/` 多架構路的差異表）。
- 2026-09-18：retire 所有 fork patch 與 PR bake（~~上游已全併入 main~~ **此判斷已於 2026-10-07 推翻**，見上條）；`Dockerfile` 改回純 `REDLIB_BRANCH=main` clone；`AGENTS.md` 同步。
- 2026-09-18：repo 結構重整為單一 app（`Dockerfile`/`docker-compose.yaml` 移到 repo 根，目錄名 = 映像名慣例）；`AGENTS.md` 更新慣例與路徑。
- 2026-09-18：多架構 build 上線（Plan B：12 機原生交叉編譯 musl + `Dockerfile.pack` + `imagetools` 合併 manifest list），雙 tag `latest`/`<git-sha>`，推 `codeberg.org/lawlietr/redlib`。文件：`design/multi-arch-build.md`、`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`。
- 2026-09-18：文檔同步 —— `design/external-services.md`（cbgproxy 已改 `:9881`、`network_mode: host`、`http_proxy` 白名單、`REDACT_PAT=1`）、`design/ci-workflow.md`（標為存檔，主線改指 `.forgejo/`）。
