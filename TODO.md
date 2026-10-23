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
- **做什麼**：把 6 支仍未 upstream 合併的上游 PR（#549/#542/#521/#560/#539/#599）bake 進建置來源；清單放 `redlib-prs.txt`（單一來源），套用邏輯放 `.build/apply_redlib_prs.sh`，由 `Dockerfile` 與 `.forgejo/scripts/build_and_push.sh` 共用。
  > **已退役**：#592（貼文頁 403 繞行）於 2026-10-22 從 `redlib-prs.txt` 移除。上游 v0.40.0 以直接 commit `0a3e9cd` 實作等效 `%2f` 繞行（同碰 `src/client.rs`）；#592 作為 PR 從未合併，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故退役、thread-403 改由上游供應。見 `RELEASE_NOTES.md` 2026-10-22 段。
- **為什麼**：2026-09-18「已全部併入 upstream main」的判斷錯誤（引用的 commit 是我們 build 內的本地 merge tip），upstream main 至今沒有這些改動 → 現行發佈映像少了 CMAF/rich:video 影片、預設 post sort 生效、lazy-load、分享連結、0 則留言 panic 修正。
- **狀態**：本輪已完成 —— 文件更正、bake 鏈接回兩條 build 路徑、本地 x86-64 編譯驗證、GitHub Actions 編譯驗證（run #10，commit `0c5050d`，ghcr + Codeberg 已發布）。#592 已退役；2026-10-23 起加回 #599，現為 6 支。
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

## P1 — GitHub 端要設 `CODEBERG_PAT` secret（鏡像 job 的前提）
- **做什麼**：在 GitHub repo → Settings → Secrets and variables → Actions → Repository secrets 新增 `CODEBERG_PAT`，值是 Codeberg 帳號（`Lawlietr`）的 PAT，權限 `write:packages`。只能由帳號持有者操作，agent 拿不到也無法代設。
- **為什麼**：`mirror-codeberg` job 靠它把 ghcr 的成品鏡像到 `codeberg.org/lawlietr/redlib`。沒設時該 job 會 exit 1（刻意不靜默略過），於是 Codeberg 的 tag 就不會更新，而 ghcr 照樣發佈 —— 兩個登錄區會開始不一致。
- **優先級**：P1（不影響 ghcr 主路徑，但 Codeberg 側鏡像全部卡住）。
- 細節：`design/github-actions-workflow.md` §9、`.github/scripts/mirror_to_codeberg.sh`。

## P2 — 在真的 arm64 硬體上跑一下 ghcr 版映像（收尾驗證）
- **做什麼**：在 arm64 機器上 `docker pull ghcr.io/lawlietr/redlib:latest`，起容器後開一個貼文頁確認。
- **為什麼**：ghcr 的 arm64 映像目前只有**靜態證據**：manifest list 有 arm64 entry，`docker cp` 出來的 binary 是 `ELF 64-bit LSB executable, ARM aarch64, statically linked`、無 INTERP、無 dynamic section。本機是 x86_64 且沒有 qemu binfmt（`tonistiigi/binfmt --install arm64` 在此主機無效，`docker run --platform linux/arm64` 會 `exec format error`），所以 arm64 版**尚未實際執行過**。ghcr 版是 glibc 靜態、和 12 機的 musl 版是不同檔案，但**同源碼且 amd64 行為已實測一致**（`/`、`/r/AskReddit/top`、`/r/gaming` 皆 200 與同大小），所以 codeberg 舊 musl 版的實測只能當參考、不能代替 arm64 驗證。CI 的 arm64 閘門有兩層：`docker cp` 出來的 binary 必須 `ARM aarch64` + 零 `NEEDED`（確定性），以及 runner 上
  qemu binfmt 存在時真的起 arm64 容器 —— 後者在 run `39551016403` 實測 `/` 回 200（qemu 模擬下能服務），
  但**這不等於真 arm64 硬體**，本項仍開放。
- **優先級**：P2（CI 與 registry 都已綠燈，只差執行驗證；codeberg 版 arm64 已在真硬體跑過）。
- 細節：`design/github-actions-workflow.md` §5（上線證據與三條路的取捨）。
## P3 — 上游 #560 分享連結的 id 條件錯誤（**已知問題，暫不處理**）
- **做什麼**：**不處理**（2026-10-21 決定），但**必須記得**：在未重新評估之前，任何地方都不能宣稱分享連結已修；要重啟就先重讀 §8.9。
- **為什麼**：上游那支 PR 的 id 長度條件只接受 8–12 字元，而現行 post short id 是 7 字元 → 兩條分享連結入口（subreddit 版與使用者版）對現代 post 一律 404，錯誤頁文字是 `Nothing here`。路由本身有註冊、有在跑（用 8 字元假 id 可探到另一種錯誤），只是條件把人擋在門外。屬上游條件錯誤，不是我們 bake 失手。
- **狀態/優先級**：P3，暫不處理（站外進來的連結壞，但站內使用不受阻）。
- 細節：`design/upstream-pr-bake.md` §8.9（決定性的兩條探測 URL）與 §2 表格的 ⚠ 注記、`design/error-triage-playbook.md` §4.1（路由偵測手法）、`RELEASE_NOTES.md` 的 pre-existing known issue 段。

## 近期完成
- 2026-10-23：**bake 上游 #599（贴文頁留言改從 shreddit HTML fragment 重建）**。背景：`0a3e9cd`（v0.40.0）的 `%2F` 繞行已被 Reddit 破掉 —— 線上實例 `/` 與 `/r/popular` 皆 200，但贴文頁 404 + `Failed to parse page JSON data…｜/r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`；上游 main 自 v0.40.0（HEAD `ba116c1`）後零 commit → 上游完全沒修，#599 是 50 支 open PR 中唯一處理此事的（AI 生成、0 review、0 check runs）。先做**靜態分析**（diff 全文阅读、檔案重疊檢查、相依存在性、`git merge --no-ff` 兩序全 clean），再**本地 x86-64 build + 容器實測**：贴文頁 200 / 206 則正文留言、permalink + `?context=3` OK、留言排序三種集合不同、0 則留言不 panic、panic 0。**已知不完整**（留言 200 則上限、無 author flair/awards、每頁 1–31 請求、冷 3.07s / 熱 0.019s、shreddit cookie session 全實例共用、subreddit 名稱不再被驗證、映像 13.5→14.8MB）。文件同步：`redlib-prs.txt`（pin `0db637cd`）、兩個 README（上游狀態新段 + 故障排除）、`RELEASE_NOTES.md`（逐條 loss 表）、`design/upstream-pr-bake.md`（§2 表格與 merge 順序、§7 新增 #599 專屬項、§8.12）。
- 2026-10-22：**退役 bake 上游 #592（貼文頁 403 繞行）**。上游 v0.40.0（2026-10-22）以直接 commit `0a3e9cd fix: encode anonymous comments request paths` 實作等效 `%2f` 編碼繞行（同碰 `src/client.rs`）；#592 作為 PR 從未合併，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故從 `redlib-prs.txt` 移除，thread-403 改由上游供應。剩餘五支 bake（#549/#542/#521/#560/#539）照常。本輪仍是五支 clean merge、不碰 `Cargo.lock`；本地 build + smoke 全過（`/`、`/r/popular`、`/r/technology`、貼文頁皆 200、negative control 404、panic 0），GitHub Actions run #10（commit `0c5050d`）六 job 全綠並原樣鏡像到 Codeberg（digest 相同）。#592 仍是 workaround 不是 root fix，re-break 風險與 observable（`client.rs` 的 `Reddit blocked this request (403 Forbidden)…`）不變。文件同步：`redlib-prs.txt`、`design/upstream-pr-bake.md`（§2/§7/§8.8）、兩個 README、`RELEASE_NOTES.md`。
- 2026-10-21：**鏡像機制上線**（`.github/scripts/mirror_to_codeberg.sh` + `mirror-codeberg` job）：GitHub 端編譯完、manifest 合併完之後，用 `docker buildx imagetools create` 把 `latest`/`<git-sha>`/`amd64`/`arm64` **原樣複製**到 `codeberg.org/lawlietr/redlib`（registry 側 copy，不重新編譯，blob 約 13MB，**digest 兩邊相同**）；缺 `CODEBERG_PAT` 時 exit 1 明確失敗。文件同步：`design/github-actions-workflow.md` 新增 §9、AGENTS.md、兩個 README 的 Tags/CI/CD/存放位置表、`docker-compose.yaml` 註解、`RELEASE_NOTES.md`。
- 2026-10-21：**煙測上線並全綠**（run `39551016403`，commit `51d0d7e`）：build (amd64)/build (arm64)/manifest/**smoke**/**mirror-codeberg** 五個 job 全成功；smoke 在 runner 上抓到 amd64 與 arm64 binary 皆 `statically linked`、`/` 200 62,216B、`/r/gaming` 200 79,425B、`/r/AskReddit/top` 200 38,012B，qemu 下 arm64 容器 `/` 也回 200；mirror 結尾打印兩邊 child digest 完全相同（`12105bec…` amd64、`d77e9225…` arm64）。第一次嘗試（run `39550258322`）失敗純粹是 smoke job 漏了 `actions/checkout`。
- 2026-10-21：**musl 退場為產品線**（workflow 與 runner 保留不變）。實測對照：ghcr 的 glibc `+crt-static`（`readelf -d` NEEDED=0、13.5MB）與 Codeberg 舊 musl 版（`15cc3c1`、13.2MB）在同一台 x86_64 上 `/`、`/r/AskReddit/top`、`/r/gaming` 全 200 且大小相同、log 無解析器錯誤 —— 靜態 glibc 在 `scratch` 的 NSS/DNS 疑慮未發生，大小也無差異，而 arm64 hosted runner 讓「x86 交叉編 arm64」這個 musl 的唯一理由消失。文件同步把 musl 降調為 `.forgejo/` 備援路的實作細節（兩個 README、AGENTS.md、`design/multi-arch-build.md`、`design/forgejo-runner-workflow.md`、`RELEASE_NOTES.md`），不建平行 tag。
- 2026-10-21：**新增 `smoke` job**（`.github/scripts/smoke_test.sh`，`needs: manifest`；`mirror-codeberg` 改 `needs: smoke`）：對已發佈鏡像做四步：`docker cp` 取出 `:amd64`/`:arm64` 的 `/redlib` 驗證**全靜態**（有 `NEEDED` 即 fail）與 arm64 架構正確 → 起容器打 `/`（200 且 body ≥ 20KB）→ `/r/gaming`、`/r/AskReddit/top`（強迫容器內 DNS + 出網 HTTPS）→ 有 qemu binfmt 時 best-effort 真的起 arm64 容器。reddit 回 403/429 只 warn（機房 IP 限流），>=500 或 log 出現解析器錯誤就 fail。**踩到的坑**：redlib **不收 CLI 參數**，`--help` 會得到 `error: unexpected argument found`，所以別用 `--help` 當存活探測（設定只從環境變數讀）。本機已完整跑過一次（exit 0）。文件：`design/github-actions-workflow.md` §10。
- 2026-10-21：**發佈主權改到 GitHub Actions**。`.forgejo/workflows/build.yml` 的 `push` trigger 移除、只留 `workflow_dispatch`（可填 reason），workflow、runner 與磁碟紀律完整保留作為 fallback 與 musl 產物來源；`codeberg.org/lawlietr/redlib` 的 tag 改由同一條 CI 的 `mirror-codeberg` job 鏡像維護。`ghcr.io/lawlietr/redlib` 成為主要映像來源（雙架構 + `<git-sha>`），README/README_EN 的部署指令、compose 註解、Tags 表、CI/CD 節與 AGENTS.md 全部改寫；新增 README 的「本地編譯與測試」章節（ smoke 四招 + 本機限制：只產本機架構、無 qemu binfmt）；GitHub workflow 加 `concurrency: ghcr-publish` 串行，避免 manifest merge 混到不同 commit 的兩個架構。
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
