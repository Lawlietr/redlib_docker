# TODO

> 本檔只放**工作進度與優先級**。每個項目 = 做什麼 + 為什麼/範圍 + 優先級，並連結到 `design/` 的實作指引。
> 詳細說明、踩坑、部署步驟一律放 `design/`，不在這裡重複。
> 本專案的 CI：本地 Forgejo（多架構發佈）+ GitHub Actions（amd64 編譯、ghcr 鏡像）。

## 優先級定義

| 級 | 含義 |
|----|------|
| **P0** | 緊急且重要：阻塞部署/上線、影響正確性或穩定性，需立即處理 |
| **P1** | 重要不緊急：影響可靠性/可觀測性/品質，近期要推但非阻塞 |
| **P2** | 有價值但可排後：改善體驗、重構、非阻塞的補齊 |
| **P3** | 想法/可選：nice-to-have、長期評估項 |

## 維護慣例
- **commit 訊息一律用英文**（conventional-commit 風格的 subject，body 也用英文）。文件照雙語慣例：README 繁中/英文、`RELEASE_NOTES.md` 英文、`design/` 繁中。
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
- **優先級**：P2（有價值、可排後；先要決策再動 build）。
- 細節：`design/upstream-pr-bake.md` §3、§4。

## P2 — 在真的 arm64 硬體上跑一下 ghcr 版映像（收尾驗證）
- **做什麼**：在 arm64 機器上 `docker pull ghcr.io/lawlietr/redlib:latest`，起容器後開一個貼文頁確認。
- **為什麼**：ghcr 的 arm64 映像目前只有**靜態證據**：manifest list 有 arm64 entry，`docker cp` 出來的 binary 是 `ELF 64-bit LSB executable, ARM aarch64, statically linked`、無 INTERP、無 dynamic section。本機是 x86_64 且沒有 qemu binfmt（`tonistiigi/binfmt --install arm64` 在此主機無效，`docker run --platform linux/arm64` 會 `exec format error`），所以 arm64 版**尚未實際執行過**。注意 ghcr 版是 glibc 靜態、和 12 機的 musl 版是不同產物，不能拿 codeberg 版的實測結果直接套用。
- **優先級**：P2（CI 與 registry 都已綠燈，只差執行驗證；codeberg 版 arm64 已在真硬體跑過）。
- 細節：`design/github-actions-workflow.md` §5（上線證據與三條路的取捨）。
## P3 — 上游 #560 分享連結的 id 條件錯誤（**已知問題，暫不處理**）
- **做什麼**：**不處理**（2026-10-21 決定），但**必須記得**：在未重新評估之前，任何地方都不能宣稱分享連結已修；要重啟就先重讀 §8.9。
- **為什麼**：上游那支 PR 的 id 長度條件只接受 8–12 字元，而現行 post short id 是 7 字元 → 兩條分享連結入口（subreddit 版與使用者版）對現代 post 一律 404，錯誤頁文字是 `Nothing here`。路由本身有註冊、有在跑（用 8 字元假 id 可探到另一種錯誤），只是條件把人擋在門外。屬上游條件錯誤，不是我們 bake 失手。
- **狀態/優先級**：P3，暫不處理（站外進來的連結壞，但站內使用不受阻）。
- 細節：`design/upstream-pr-bake.md` §8.9（決定性的兩條探測 URL）與 §2 表格的 ⚠ 注記、`design/error-triage-playbook.md` §4.1（路由偵測手法）、`RELEASE_NOTES.md` 的 pre-existing known issue 段。

## 近期完成
- 2026-10-21：**發佈主權改到 GitHub Actions**。`.forgejo/workflows/build.yml` 的 `push` trigger 移除、只留 `workflow_dispatch`（可填 reason），workflow、runner 與磁碟紀律完整保留作為 fallback 與 musl 產物來源；`codeberg.org/lawlietr/redlib` 的 tag 從此起會落後（刻意）。`ghcr.io/lawlietr/redlib` 成為主要映像來源（雙架構 + `<git-sha>`），README/README_EN 的部署指令、compose 註解、Tags 表、CI/CD 節與 AGENTS.md 全部改寫；新增 README 的「本地編譯與測試」章節（ smoke 四招 + 本機限制：只產本機架構、無 qemu binfmt）；GitHub workflow 加 `concurrency: ghcr-publish` 串行，避免 manifest merge 混到不同 commit 的兩個架構。
- 2026-10-21：**ghcr 也變成雙架構 + 可 pin**（commit `d572b2e`，run `39543407871`，build (amd64) / build (arm64) / manifest 三 job 全綠）。做法是**原生 arm64 hosted runner**（`ubuntu-24.04-arm`，public repo 自 2025-08-07 免費 GA），不用 QEMU、不用交叉工具鏈，arm64 job 全程約 4 分鐘。tag 現在與 codeberg 版完全對齊：匿名 `tags/list` → `latest`/`arm64`/`amd64`/`d572b2e`，且 `latest` 與 `<git-sha>` 都是 `manifest.list.v2`（entries = amd64 + arm64）。新增 `.github/scripts/merge_manifest.sh`（`docker buildx imagetools create`），`build_and_push.sh` 改成吃 `ARCH`。⚠ ghcr 版是 **glibc 靜態** binary（與 12 機的 musl 版是不同產物，digest 不可比）；靜態驗證已做，執行驗證見上方 P2。
- 2026-10-21：**GitHub repo 與 ghcr package 轉為 public**（使用者在 UI 手動翻轉；此前 repo private → package 默默繼承 private，匿名拉取會被 `denied`，很容易誤判成「映像不存在」）。複驗（完全匿名、不帶憑證）：`docker pull ghcr.io/lawlietr/redlib:latest` 成功，digest `sha256:93606cc4…` **與 Actions log（run 39534174002 / commit 15cc3c1）完全一致** → 公開的就是含 #592 那輪；跑起來後貼文頁 200、0 則留言 permalink 200、負 control 404、無 panic。同步把 `design/github-actions-workflow.md` §3/§8 與兩個 README 的 ghcr 段落從「private / 需 `read:packages` token」改為公開現況（仍是 amd64-only、只有 `latest`）。公開後做了 secrets 健檢：全歷史 232 個 blob 掃 token/私鑰 pattern → **0 命中**，`.env.example` 內容全空，CI 只用 `${{ secrets.* }}`。
- 2026-10-21：**逐功能線上核對跑完**（對 `https://ddit.avpclub.uk` 與本地同映像容器）。通過：影片 proxy 的大寫 `CMAF`/`DASH` 路徑（206 `video/mp4`）、舊 `/vid` 路徑 404、0 則留言 permalink 不 panic、`loading="lazy"` 且無 SVG 包裝、路徑式排序正常、預設 post sort 對新訪客生效（用**只抽掉 #521** 的對照映像定因：抽掉後 env 失效）。順帶定因兩個**非回歸**：`?sort=` 向來是 no-op（含/不含 #521 都一樣）、不存在的 sub 回 200 空頁屬上游行為（線上與本地 byte 數一致）。未通過一項：分享連結（見上方 P1 條目）。
- 2026-10-21：**雙架構上線確認** —— amd64 與 arm64 的 redlib container 都已架起來，實測兩個架構都正常運行（跑的是含 #592 的六支 bake 映像）。逐功能線上核對（影片 proxy、panic、post sort、分享連結、lazy-load）仍未做，保留在上方 P1 條目。
- 2026-10-21：**bake 上游 #592 修好貼文頁**（Reddit 對匿名 client 的路徑規則封鎖 → 前端 parse error）。六支 Tier 1 累積 `--no-ff` 全 clean；本地雙映像 A/B 實測（對照組精確重現舊錯誤、含 592 組 200 + 留言正常 + 回歸清單全過）；`redlib-prs.txt` 加行、`upstream-pr-bake.md` §2/§7/§8 同步（§8.8 記錄**繞行**屬性、再壞的觸發條件與 observable 字串）；新增 `RELEASE_NOTES.md`（英文）說明這只是暫緩之計而非真正修正，README 雙語加指針與警告。
- 2026-10-21：**新增 `design/error-triage-playbook.md`** —— 從「貼文頁 parse error」事件沉澱出可重現的溯源 SOP：錯誤訊息→呼叫點映射、上游 PR 基底檢查、**含/不含候選 PR 的雙映像端到端 A/B**（取代裸 curl 探測，後者在無合法 token 時會給假陰性）、固定回歸清單（含負 control 要回正確 404 而非 parse error）、tier 判定與記帳要求（繞行 vs 根治、observable 字串）。
  後續又補了 §4 grep 陷阱（錯誤頁範本自帶 parse error 錯誤訊息文字→假陽性）與 §4.1 逐功能核對四招（素材從站內 HTML 挖、用符合條件的假 id 探路由、對照映像只抽被懷疑的那一支、byte 數一致則屬上游行為）。
- 2026-10-07：**更正 9/18 的 bake 退役判斷**（上游 main 未含那 5 支 PR）；重新接回 bake 鏈，改用上游 PR 取代原 fork port 計畫的 C/D1 子集；新增 `redlib-prs.txt` + `.build/apply_redlib_prs.sh` 供 `Dockerfile` 與多架構腳本共用；兩條 workflow 的觸發路徑補上清單與 `.build/**`；新增 `design/upstream-pr-bake.md`。
- 2026-10-07：**GitHub 遠端上線**（`github.com/Lawlietr/redlib_docker`，private），push 觸發 `.github/workflows/build.yml` 在 `ubuntu-latest` 原生編 amd64 並推 `ghcr.io/lawlietr/redlib:latest`；workflow 補 `packages: write`（首次建立 ghcr package 所需）。文件：`design/github-actions-workflow.md` 全面更新（含與 `.forgejo/` 多架構路的差異表）。
- 2026-09-18：retire 所有 fork patch 與 PR bake（~~上游已全併入 main~~ **此判斷已於 2026-10-07 推翻**，見上條）；`Dockerfile` 改回純 `REDLIB_BRANCH=main` clone；`AGENTS.md` 同步。
- 2026-09-18：repo 結構重整為單一 app（`Dockerfile`/`docker-compose.yaml` 移到 repo 根，目錄名 = 映像名慣例）；`AGENTS.md` 更新慣例與路徑。
- 2026-09-18：多架構 build 上線（Plan B：12 機原生交叉編譯 musl + `Dockerfile.pack` + `imagetools` 合併 manifest list），雙 tag `latest`/`<git-sha>`，推 `codeberg.org/lawlietr/redlib`。文件：`design/multi-arch-build.md`、`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`。
- 2026-09-18：文檔同步 —— `design/external-services.md`（cbgproxy 已改 `:9881`、`network_mode: host`、`http_proxy` 白名單、`REDACT_PAT=1`）、`design/ci-workflow.md`（標為存檔，主線改指 `.forgejo/`）。
