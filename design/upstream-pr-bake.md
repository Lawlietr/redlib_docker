# 上游 PR bake（Tier 1）：靜態分析、來源、漂移重做程序

> 本檔取代 `design/fork-patch-dash-cmaf-bugfixes.md` 的 **C 組（DASH/CMAF）** 與 **D1** 兩項：
> 上游已有現成 PR，不必再從 fork 手工 port。fork 檔僅殘 D2/D4/D5 需要自製 patch。

## 0. 摘要（為什麼要重開 bake）

2026-09-18 曾以「#506/#521/#560/#539/#549 已全部併入 upstream main（至 `8167e00`）」為由退役 bake 鏈。
**該判斷錯誤**：

- `8167e00 "Merge PR#549"` 不存在於 upstream repo；它是**我們自己 Docker build 內** `git merge -X ours pr549 --no-ff -m "Merge PR#549"` 產生的**本地 merge tip**（見本 repo `fa6d4f3` 的 bake 鏈）。
- 2026-10-07 複核：upstream `main` HEAD 仍是 `a4d36e9`（2026-04-24，"Merge pull request #508"），其後**無任何新 commit**；51 支 open PR 用 `git cherry` 比對，**0 支 patch-applied**。
- 內容檢核：main 的 `src/utils.rs` 無 `CMAF`、無 `rich:video`，`format_url` 的 `/vid/` capture arity 仍是 **2**。

→ 結論：那 5 支 PR 至今未進 main，**2026-09-18 之後建出的映像少了這些功能**。本檔把 bake 重新接回，並改用**上游 PR**（而非 fork commit）作為來源。

## 1. 靜態分析程序（可重現）

```bash
# 1) 上游 clone + 所有 PR refs
git clone --filter=blob:none https://github.com/redlib-org/redlib.git upstream
git -C upstream fetch origin '+refs/pull/*/head:refs/pr/*'

# 2) open PR 清單（GitHub API）
curl -s "https://api.github.com/repos/redlib-org/redlib/pulls?state=open&per_page=100"

# 3) 逐支判斷「是否已在 main」：ancestor + patch-equivalence
git -C upstream merge-base --is-ancestor refs/pr/<n> main && echo IN_MAIN
git -C upstream cherry main refs/pr/<n> | grep -c '^-'      # >0 = 已套用

# 4) 對現行 main 的衝突性（無副作用）
git -C upstream merge-tree --write-tree main refs/pr/<n>    # 首行是 tree sha = CLEAN

# 5) 累積 merge 實測（真實 merge，非 dry-run）
git -C upstream checkout -q -b bake main
while read -r pr _; do git -C upstream merge --no-ff "refs/pr/$pr" -m "Merge PR#$pr"; done < redlib-prs.txt
```

2026-10-07 實測數字：open PR **51** 支 → 對現行 main **35 支 clean、16 支衝突**；Tier 1 五支**全部 clean**，且**不碰 `src/client.rs`、不碰 `Cargo.lock`**（`--locked` 不受影響）。

## 2. Tier 1：已 bake（`redlib-prs.txt`）

| PR | 上游 head（分析時） | 內容 | 對我們的影響 |
|----|---------------------|------|--------------|
| [#549](https://github.com/redlib-org/redlib/pull/549) | `9703ca81` | `REGEX_URL_VIDEOS` → `(DASH\|CMAF)`；route `/vid/:id/:size` → `/vid/:id/:prefix/:size`；`format_url` 加 3-segment capture；`post_hint == "rich:video"` 走 preview fallback；**並同步更新 `format_url` 測試** | CMAF 影片不再掉成不 proxy 直鏈；外部轉檔媒體可用。**breaking**：舊 `/vid/{id}/{size}` 消失 |
| [#542](https://github.com/redlib-org/redlib/pull/542) | `29c9bda4` | `templates/post.html`：`single_thread && comments.len() > 0` | 修 0 則留言 permalink 的 panic（= 原 fork patch D1） |
| [#521](https://github.com/redlib-org/redlib/pull/521) | `93c03bb1` | `src/subreddit.rs`：`post_sort` 由 `req.cookie("post_sort")` 改 `setting(&req, "post_sort")` | **`REDLIB_DEFAULT_POST_SORT` 不必先存設定才生效**（直接關係本 repo 的 env） |
| [#560](https://github.com/redlib-org/redlib/pull/560) | `7a284d30` | 新增 `/u/:name/s/:id` 分享連結處理（id 長度 guard `(8..12)`） | ⚠ **實際上用不了**：現行 post id 是 7 字元 → 一律 `Nothing here` 404；既有的 `/r/:sub/s/:id` 同病。見 §8.9 |
| [#539](https://github.com/redlib-org/redlib/pull/539) | `514202ad` | `templates/utils.html` 移除 `<svg><image>` 包裝，改直出 `<img loading="lazy">` | 圖片 lazy-load；同時覆蓋原 fork patch D3 的 SVG 部分 |
| [#599](https://github.com/redlib-org/redlib/pull/599) | `0db637cd` | 新增 `src/shreddit.rs`（719 行）+ `src/client.rs` 的 `shreddit_fragment()`：貼文改 `/by_id/t3_<id>.json`、**留言改抓 Reddit 前端自己的 `/svc/shreddit/comments/...` HTML fragment** 用 `scraper` 重建原 JSON 形狀；cookie session 輪替 + captcha 偵測；`Cargo.toml` 加 `scraper 0.29` 與 wreq `cookies` feature | 貼文頁留言恢復（`%2F` 繞行已被 Reddit 識破後唯一可行的上游方案）。⚠ **繞行、且不完整**：200 則上限、無 flair/awards、每頁 1–31 請求、subreddit 不驗證。詳 §8.12 |
| [#592](https://github.com/redlib-org/redlib/pull/592) | `1e9515eab8d0` | `src/client.rs`：`encode_thread_route()` 把 `/r/<sub>` 與 `comments` 之間那**一個** slash 編碼成 `%2f`（放進 `json()` 入口，涵蓋所有呼叫者）；另加 `non_json_response_error()` 把 403 區塊頁報成「Reddit blocked this request (403 Forbidden)…」而非 parse error。附 5 個純函式測試 | **貼文頁恢復可用**（此前所有實例的 `/r/x/comments/<id>/…` 全數 403 → 前端 `Failed to parse page JSON data: expected value at line 1 column 1`）。⚠ **這是繞行，不是根治**，見 §8.8。
> **2026-10-22 退役**：上游 v0.40.0 以直接 commit `0a3e9cd fix: encode anonymous comments request paths` 實作等效 `%2f` 繞行（同碰 `src/client.rs`）。#592 作為 **PR 從未合併**，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故已從 `redlib-prs.txt` 移除；thread-403 現由上游 `0a3e9cd` 供應。見 §8.8。 |

**merge 順序 = `redlib-prs.txt` 檔內順序**（549 → 542 → 521 → 560 → 539 → 599）。六支檔案重疊極少（549 與 560 同碰 `src/main.rs` 但不同區塊），實測 `--no-ff` 全 clean；2026-10-23 以 `git merge --no-ff` 驗證过 **#599 放最後與放第一個都是 six-way clean**（#599 只碰 `client.rs`/`post.rs`/`lib.rs`/`shreddit.rs`/`Cargo.*`，與其餘五支零重疊），本地 `docker build` 亦 exit 0（`--locked` 未報 lock 不一致）。
> 注：#592 原先與 549 同碰 `src/client.rs` 但不同區塊；2026-10-22 退役後 bake 鏈一度不碰 `src/client.rs`，thread-403 繞行改由上游 `0a3e9cd`（v0.40.0）供應。**2026-10-23：`0a3e9cd` 那招已被 Reddit 識破**（正式實例的貼文頁又回到 `Failed to parse page JSON data: expected value at line 1 column 1 | /r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`），而上游 main 自 v0.40.0（HEAD `ba116c1`）後零 commit → 只能 bake #599。
> 註：#592 原本與 549 同碰 `src/client.rs` 但不同區塊；2026-10-22 退役後 bake 鏈不再碰 `src/client.rs`，該檔的 thread-403 繞行由上游 `0a3e9cd`（v0.40.0）供應。

> 不用 `-X ours`：舊 bake 鏈用 `-X ours` 是因為那些 PR 基於 pre-wreq 的 main；現在六支都 clean，`-X ours` 只會**靜默吃掉 upstream 改動**（正是 pr509 那棵樹悄悄留著 pre-wreq `client.rs` 的教訓）。

## 3. Tier 2：可選，尚未 bake（需決策）

| PR | 內容 | 取捨 |
|----|------|------|
| [#572](https://github.com/redlib-org/redlib/pull/572) | RSS media 重構：`utils::build_rss_item()` 共用，subreddit + user feed 都帶 enclosure（作者 = feld，redlib 原作者） | 要 RSS 媒體就取這支，**並跳過 #563**（同目的、較舊） |
| [#568](https://github.com/redlib-org/redlib/pull/568) | `REDLIB_SOURCE_URL`（footer 原始碼連結可設定） | 自架實用、+28/−10、clean |
| [#566](https://github.com/redlib-org/redlib/pull/566) | `geo_filter` 偏好 + `REDLIB_DEFAULT_GEO_FILTER` | 會新增 env → 需同步 `.env.example` 與 AGENTS.md 表 |
| [#577](https://github.com/redlib-org/redlib/pull/577) | Reddit onion service（`REDLIB_USE_TOR`），base = 現行 main，2026-10-07 仍活躍 | 與先前「不採用 fork 的 Tor」決策同類，但這是上游原生、env 可關；抗 Reddit 封鎖 → 需明確決策 |
| [#564](https://github.com/redlib-org/redlib/pull/564) | 每頁文章數可設定（`REDLIB_DEFAULT_POSTS_PER_PAGE`） | 上游自標 **WIP**，暫不取 |
| [#578](https://github.com/redlib-org/redlib/pull/578) | 依 client 要求回 Markdown | +458/−41、15 檔，先觀望 |

## 4. Tier 3：不採用（記錄理由，避免重複評估）

- **#506**（CMAF）→ 被 #549 取代（#549 是超集，含 rich:video 與測試更新）。
- **#563**（user RSS enclosure）→ 被 #572 取代。
- **#509**（hyper-tls）→ 已被 main 的 wreq 遷移取代，**不可再加回**。
- **#548**（Axum/Hyper v1 重構）→ 作者標記 unfinished/abandoned。
- **#378 / #538**（light+dark 分離、Catppuccin 主題）→ 與先前「不採用 fork E 類主題」一致。
- **#580**（MinGW target）、**#439/#476/#492/#552/#435/#133/#556/#579/#581/#576/#486/#410**（nix / devcontainer / deps / docs / README）→ 不影響我們的映像。
  - 例外參考：**#581**（上游自己的 `Dockerfile.*` 重寫）值得讀：musl 改 `rust:alpine` + `RUSTFLAGS="-C target-feature=-crt-static -C link-self-contained=no"`，並註明缺 `libgcc` 會 undefined symbols 當機 —— 與我們 arm64 musl-cross-make + boring-sys2 的踩坑同源（`design/multi-arch-build.md`）。
- 其餘 2024 年舊 PR（#179/#181/#194/#254/#290/#291/#298/#394/#396/#400/#413/#422/#454/#460/#507/#517/#520/#524）→ 過舊或屬大型功能，不評估。

## 5. 上游漂移時的重做程序（`git merge` 衝突 / head 漂移警告）

1. 看 build log：`apply_redlib_prs.sh` 會印出每支 PR 的實際 head SHA；與 `redlib-prs.txt` 不符會印 `warning: PR #<n> head moved`。
2. 重跑 §1 的步驟 1–5，確認：該 PR 是否**已真的進 main**（`git cherry` 出現 `-`）→ 若是，從 `redlib-prs.txt` 移除該行。
3. 若仍 open 但衝突：在 scratch clone 把 PR rebase 到新 main、解衝突，改採「本 repo 自製 patch」或改採別支（例：#549 若死掉就退回 #506）。
4. 更新 `redlib-prs.txt` 的 head SHA 欄與本檔 §2 表格。
5. 重新跑本地 build（§6）與線上驗證（§7）。

## 6. 實作位置（單一來源）

| 檔 | 角色 |
|----|------|
| `redlib-prs.txt` | **唯一 PR 清單**（PR 編號 + 分析時 head SHA + 一行說明） |
| `.build/apply_redlib_prs.sh` | 在 clone 好的 redlib 樹上依清單 `git fetch pull/<n>/head` + `git merge --no-ff`；head 漂移會 warn，衝突直接失敗 |
| `Dockerfile` | `COPY redlib-prs.txt .build/apply_redlib_prs.sh` → clone（`--depth 300`）→ 呼叫腳本。**本地 build 與 GitHub Actions amd64 build 都走這條** |
| `.forgejo/scripts/build_and_push.sh` | 多架構路徑不用 Dockerfile，故 clone 後**另外**呼叫同一支腳本（兩條路徑內容必須一致） |
| `.forgejo/workflows/build.yml`、`.github/workflows/build.yml` | 觸發路徑含 `redlib-prs.txt`、`.build/**` |

前提：`REDLIB_SRC` 必須是 GitHub 上的 redlib repo —— `refs/pull/*` 只在那裡存在。換 mirror 時 bake 會失敗（這是刻意的）。

## 7. 驗證 checklist

**本地（x86-64，工具鏈在容器內）**
- [x] `docker build -t redlib:local-test .` 成功；log 中出現 6 行 `Merging PR #<n> -> <sha>` 且無 `warning:`（2026-10-23 起為 6 支（含 #599）；2026-10-22 為 5 支；更早含 #592 時是 `Baked 6 PR(s)`）
- [x] `docker run --rm --entrypoint /redlib redlib:local-test --help` 可執行（2026-10-21 以更強的證據取代：published 映像 `codeberg.org/lawlietr/redlib:15cc3c1` 實際起服務並回應請求）
- [x] 靜態確認 baked 樹：`CMAF`、`rich:video`、`/vid/:id/:prefix/:size`、`comments.len() > 0`、`setting(&req, "post_sort")`、`/u/:name/s/:id` 都在
  （2026-10-21 以更強的 **runtime 證據**取代靜態 grep：六項都在線上映像上觀察到行為——大寫 `CMAF`/`DASH` prefix 的 `/vid/` 連結、`/u/:name/s/:id` 路由已註冊（拿 8 字元 id 探得到）、`REDLIB_DEFAULT_POST_SORT` 生效、`loading="lazy"` 且無 `<svg><image`）

**線上（部署後）**（2026-10-21 已在 `https://ddit.avpclub.uk` 逐項跑過；需要特定 env 的項目在**本地同映像容器**補測）
- [x] CMAF 影片 post → `/vid/{id}/CMAF/{size}.mp4` 正常（`/vid/00npr2ko1nwh1/CMAF/1080.mp4` → 206 `video/mp4`，用 Range 請求）；DASH → `/vid/{id}/DASH/{size}.mp4` 正常（`/vid/v0ckpi39w0db1/DASH/1080.mp4` → 206 `video/mp4`）。
  注意 prefix 是**大寫** `CMAF`/`DASH`（取自 Reddit 的 media 標記），不是小寫
- [x] 0 則留言 post 的 permalink 不 panic（#542）：`/r/capybara/comments/1xahdap/`、`/r/capybara/comments/1x89e79/`（皆 0 則留言）與 `…/1xahdap/x/` → 200、留言區塊 0 個、無 panic 頁
- [x] 未存過設定的新訪客：`REDLIB_DEFAULT_POST_SORT` 生效（#521）——**用對照映像定因**：同 sub 同刻，
  含 #521 的映像設 `REDLIB_DEFAULT_POST_SORT=new` 後順序明顯改；不含 #521 的映像設了也**無效**（順序跟未設一模一樣）
- [ ] `/u/<user>/s/<postid>` 分享連結正確導向 —— **未通過**：上游 #560（加上既有的 `/r/:sub/s/:id`）的 id 長度 guard 把現行 7 字元 post id 全部拒掉，詳 §8.9
- [x] 文章圖片帶 `loading="lazy"`，版面不破（#539 改了 post media 的 DOM 結構）：貼文頁 3 個 `<img loading="lazy" …>`、`<svg><image` 包裝 0 個
- [x] 貼文頁 `/r/<sub>/comments/<id>/<slug>/` 200 且留言正常：2026-10-23 起由 **bake #599** 供應（上游 `0a3e9cd` 的 `%2F` 繞行已被 Reddit 破掉）；本地實測 `/r/masseffect/comments/1xbt0if/its_over/` → 200 / 237KB / **206 則有正文的留言**
- [ ] **#599 專屬（2026-10-23 本地已跑，上線後需重跑）**：
  - [x] 留言 permalink `…/<slug>/<comment_id>/?context=3` → 200（實測 113 KB、目標留言有標到）
  - [x] 留言排序三種真的不同集合（`?sort=confidence` 223 / `new` 205 / `top` 215 個留言塊，首則也不同）
  - [ ] 200 則上限：大討論串會剩「More replies」殘根（本地 93–106 個）→ 上線後確認可接受
  - [ ] subreddit 名稱不再被驗證：`/r/__totally_wrong_sub__/comments/1xbt0if/x/` 本地回 **200 並顯示 r/masseffect 那篇**（上游 `main` 是 404）→ 上線後確認不會造成誤導性連結
  - [ ] 請求放大成本：本地**冷 3.07s / 熱 0.019s**（listing 0.74s）→ 上線後看真实流量下的延遲與 rate-limit 訊息頻率
  - [ ] 留言缺 author flair / awards（外观退步，非功能錯誤）
- [x] 不存在的 **post** → 正確的 Reddit 404 錯誤頁（不是 parse error；原 #592 第二個 commit 的錯誤分級，現由上游 `client.rs` 供應）。
  不存在的 **sub** 則回 **200 空頁**——上游/Reddit 側行為，線上跟我們自己的容器 **byte 數完全一致**（6958），
  跟已退役的 #592 無關（原 `encode_thread_route()` 只改寫含 `/comments` 的路徑）
- [x] 列表端點未受 #592 影響：`/r/<sub>`、`/r/popular`、`/r/all`、`/search`、`/u/<user>`、`/r/<sub>/duplicates/<id>`（2026-10-21 全部 200）
- [x] 舊 `/vid/{id}/{size}` 連結 → 404（**已知 breaking**，見 §8）：`/vid/00npr2ko1nwh1/1080.mp4`、`/vid/1qc7bbd5rowh1/480.mp4` → 404
- [x] 路徑式排序正常：`/r/<sub>`、`/new`、`/top?t=day`、`/controversial?t=week` 順序各不同（`rising` 在小 sub 可能跟 hot 重合，不計）

> 2026-10-21：**上線確認已完成於兩個架構**——amd64 與 arm64 的 container 都已架起來、實測兩邊都正常運行（`codeberg.org/lawlietr/redlib:latest` = `15cc3c1`，同一個 manifest list）。
> 逐功能核對也已跑完（見上方打勾情形）。**目前唯一未通過的是分享連結**，其性質是上游 PR 自身的 guard 條件錯誤，不是我們的 bake 失手（見 §8.9）。

## 8. 風險 / Gotchas

1. **`/vid` 路徑變更（breaking）**：`/vid/{id}/{size}` → `/vid/{id}/dash|cmaf/{size}`。站內連結由 `format_url` 產生新格式，站內無問題；外部收藏/快取的舊 proxy 連結會 404。
2. **#521 改變 post_sort 來源**：從 cookie 直讀改成 `setting()`（prefs 合成後的結果）。需回歸 `/r/x/?sort=` 與「未存設定的新訪客」兩條路徑。
3. **PR head 會動**：open PR 可能被 force-push。`redlib-prs.txt` 的 SHA 欄只用於**警示**，build 仍抓最新 head；要完全重現某次映像，用 registry 的 `<git-sha>` tag，或把 `REDLIB_BRANCH` 釘死 + 手動 fetch 指定 SHA。
4. **`--depth 300`**：shallow clone 必須夠深才能找到舊 PR 的 merge base（目前 PR 的 merge base 距 main HEAD 約 8 個 commit，300 很寬）。若 `git merge` 出現「unrelated histories」類錯誤 → 加大 depth。
5. **兩條 build 路徑要同步**：`Dockerfile`（glibc 靜態，amd64）與 `.forgejo` 腳本（musl 交叉編譯，amd64+arm64）都必須讀同一份 `redlib-prs.txt`，否則 CI 映像與本地映像內容不同。
6. **clean merge ≠ 語意正確**：五支既有 bake PR 沒有一支碰 `src/client.rs`（改動落在模板、`main.rs`、`subreddit.rs`、`utils.rs`），都沒碰 `Cargo.lock`，風險低；thread-403 繞行由上游 `0a3e9cd` 供應（#592 已退役）。**2026-10-23 起這個陳述不再適用於整條 bake 鏈**：#599 碰了 `src/client.rs`、`src/post.rs`、新增 `src/shreddit.rs`，**也碰 `Cargo.toml` 與 `Cargo.lock`**（新增 `scraper` 等 25 個 crate）→ `--locked` 一貫性變成需要留意的項目（本輪本地 build 已 exit 0，但上游 main 漂移後可能需重新生成 lock）。風險與不完整清單見 §8.12。仍需一次真實編譯（§7）與一次雙映像 A/B（`design/error-triage-playbook.md` §3）才算數。
7. **參數路徑**：`apply_redlib_prs.sh` 會先 `cd` 進 source 目錄才讀 PR 檔，所以兩個參數一律先 `realpath` 解析。
   `.forgejo` 那條路徑傳的是**相對**路徑（`redlib-src` / `redlib-prs.txt`），Dockerfile 傳**絕對**路徑 —— 兩種都要測
   （2026-10-07 就是相對路徑在 12 runner 上炸 `redlib-prs.txt: No such file or directory`）。
8. **#592（thread-403 `%2f` 繞行）已退役，改由上游供應**：原 #592 只是把 slash 編碼成 `%2f` 去**避開 Reddit 邊緣節點的路徑匹配規則**，Reddit 的政策方向是把這類資料推向登入後才能取用。2026-10-22 上游 v0.40.0 以直接 commit `0a3e9cd` 實作等效繞行（同碰 `src/client.rs`），#592 從 `redlib-prs.txt` 退役，thread-403 現由上游 `0a3e9cd` 供應。再壞的觸發條件與處置（對上游 `0a3e9cd` 同樣適用）：
   - Reddit 開始 normalise 該編碼（把 `%2f` 還原成 `/` 再比對路徑）→ 貼文頁再度全數失效。屆時**不會**再出現誤導性的 parse error，而是 `Reddit blocked this request (403 Forbidden): Reddit now requires a logged-in session for this endpoint | <path>`（來自 `client.rs` 的 `non_json_response_error()`）——**下次使用者回報先 grep 這個字串**，就能直接判定「繞行失效」而不是新故障。
   - 上游同一事件還標明**不在該 commit 範圍**的鄰居問題：首頁 `hot.json` 的 parse error（上游 #589）、Anubis PoW 擋程式化存取（上游 #567）。本機 2026-10-21 實測這兩個端點仍正常，但別誤以為一併修好。
9. **#560（分享連結）實際上用不了：上游 PR 自己的 id 長度 guard 錯了**（2026-10-21 逐功能核對發現，§7 那一項因此仍未打勾）。
   `src/main.rs` 的 `app.at("/u/:name/s/:id")` 用的是 `Some(id) if (8..12).contains(&id.len())`，而 Reddit 現行的 post short id 是 **7 字元**（例：`1x89e79`）→ 一律落到 `_ => error(req, "Nothing here")`，回 404。
   決定性證據（同一支映像上）：`/u/trewqpoiuuy/s/1x89e79`（7 字元）→ `Error: Nothing here`；`/u/trewqpoiuuy/s/1x89e79a`（8 字元、不存在）→ `Error: Post ID is invalid. It may point to a post on a user that has been banned.`
   → 路由有註冊、有在跑，**只有長度 guard 把人擋在門外**。既有的 `/r/:sub/s/:id`（ subreddit 版分享連結）用的是同一個 `8..12` 條件，所以**兩種分享連結現在都壞**。
   這不是我們 bake 造成的（#560 之前那條 route 根本不存在），但 bake #560 等於**沒辦法**宣稱「分享連結已修」。
   處理方向（尚未做）：自製 patch 把條件改成含 6–7 字元（Reddit 舊 post 有 5–6 字元 id），或上游開 issue；屬於 `design/fork-patch-dash-cmaf-bugfixes.md` 那類自製 patch（新 D 項）。
   **2026-10-21 決定：暫不處理**（不寫 patch、不提上游 issue）。但這一項**不得從記憶裡消失**：
   未重新評估前，README／release note／commit 訊息都不能宣稱分享連結已修；`redlib-prs.txt` 中的 #560 仍保留
   （那條 route 對現行 id 永遠不匹配，等於死路但無害），TODO 已把它記在 P3「已知問題，暫不處理」。
10. **`?sort=` 查詢參數向來是 no-op，與 #521 無關**（2026-10-21 定因）：含 #521 與不含 #521 的兩支映像，`/r/<sub>?sort=new` 與 `?sort=top` 都跟預設順序相同；會變的是**路徑式**排序（`/new`、`/top?t=day`、`/controversial?t=week`）。
    → §8.2 当初要求的「回歸 `/r/x/?sort=`」可以結了：**那是上游一向不支援的入口，不是 #521 的回歸**。以後別再為這個查 bake。
11. **Reddit 側的 degenerate 資料會渲染成怪頁面，不是在我們這層**（2026-10-21 記錄，供下次分流用）：
    - 不存在的 sub → **200 空頁**（不是 404）。線上與本地同映像 **6958 bytes 完全一致** → 上游行為。
    - 某些 sub（例：`r/DeathByCapybara`）的列表渲染出**空 subreddit、空作者、空 permalink** 的 post（`href=""`、`r/`、`u/`）→ Reddit 回傳的 stub 資料；同樣在本地同映像重現（9098/9100 bytes 等級）。想要那種 sub 的可用列表，得在上游處理，不是我們的 bake 問題。

12. **#599（shreddit fragment）——贴文頁留言的目前唯一可行上游方案，但它不是根治，也不完整**（2026-10-23 bake）：
    - **背景**：Reddit 把匿名 client 的 comments API 全數 403，**连带 `%2F` 编码绕行也被破**（上游 v0.40.0 的 `0a3e9cd` 失效）。
      定因方式：线上 `/`、`/r/popular` = 200，贴文頁 = 404 + parse error（`…/.json?&raw_json=1`）→ 仍是**按路徑**的封鎖。
      本機 curl 對 Reddit 所有端點（含 `by_id`、`/svc/shreddit/`）一律 403 同一份 block page → 對本機 IP 而言裸 curl **無區辨力**（playbook 假陰性）。
    - **機制**：贴文走 `/by_id/t3_<id>.json`；留言走 `www.reddit.com/svc/shreddit/comments/r/<sub>/t3_<id>[/t1_<cid>]`，
      用 `scraper` 把 `<shreddit-comment>` 重建為原 JSON 形狀（`parse_comments`/模板不改）；「More replies」以 `more-comments` POST + 隱藏 `cursor`
      做 BFS，上限 `CRAWL_LIMITS = {200 留言, 30 expansions, 10 併發}`；cache 30s；反限流靠**自己的 cookie jar**（wreq `cookies`），
      `x-ratelimit-remaining < 20` / 429 / 比對到 captcha 頁面標題字串就輪替 session 再重試一次。
    - **分級：繞行（workaround），不是 root fix**。re-break 觸發條件：（a）Reddit 關掉或改格式 `/svc/shreddit/` fragment；
      （b）captcha 頁的 title 字串改寫（它靠字面比對判 captcha，一改就會把 challenge 頁當留言內容解析）；（c）`by_id/t3_<id>.json` 也被封。
    - **observable（下次要 grep 的）**：`Reddit returned <status> | /svc/shreddit/...`（(a)/(c)）、
      `Reddit is rate limiting comment requests. Try refreshing in a few seconds.`（配額耗盡）、
      `Refusing to fetch non-shreddit path`（路徑守衛）、旧的 `Failed to parse page JSON data: expected value at line 1 column 1`（`by_id` 也被封）。
    - **已知不完整（本機實測）**：留言 200 則上限（大讨論串剩 93–106 個未展開殘根）；留言無 author flair/awards；
      每個未 cache 的贴文頁 1–31 個請求（**冷 3.07s / 熱 0.019s**，listing 0.74s）；`SHREDDIT_SESSION` 是 process-global
      → 同實例所有訪客共用一份配額；**subreddit 名稱不再被驗證**（錯 sub + 對 post id 回 200 並渲染別篇文章）；
      quarantined sub 未測；映像 13.5MB → 14.8MB（新增 25 個 crate）。
    - **信任面**：留言 `body_html` 改由 fragment 的 `inner_html()` 產生，而 redlib 對 `body_html` 是 `|safe` 渲染且**不做 sanitize**（无 ammonia）
      → 信任對象從「Reddit API 的 body_html」變成「Reddit 前端 fragment 的渲染結果」。
    - **品質風險**：上游 PR 為 **AI 生成、0 review、0 check runs**（head `0db637cd` 没被任何 CI 编譯過）；
      我们的 `--locked` 本地 build 已通过（PR 自带的 `Cargo.lock` 自洽，含 `cookie` 進 wreq deps + 25 個新 package），
      但 **不保证未来上游 main 漂移後 lock 仍自洽** → head 漂移動會 warn（`redlib-prs.txt` 已 pin）。
    - **退出策略**：若 Reddit 封掉 shreddit 或 #599 被 force-push 成不能用，從 `redlib-prs.txt` 移除该行即可（`client.rs`/`post.rs` 回到上游 v0.40.0 形態）；
      届时贴文頁會回到 parse error，**不要重啟容器當解法**。

## 9. 與 fork patch 計畫（P1）的關係

| 原 fork 子集 | 現在 |
|---|---|
| C：DASH/CMAF | **由 #549 取代**（上游原生、含 rich:video 與測試） |
| D1：0 則留言 panic | **由 #542 取代**（內容完全相同） |
| D3：overflow / SVG→img | #539 覆蓋 SVG→img 部分；`min-width/max-width` 等 CSS 仍需自製 |
| D2：重複 `id="sort"` | 上游無對應 PR → 自製 |
| D4：`location.hash` deep-link | 上游無對應 PR → 自製 |
| D5：`oauth.rs` `android_version` `9..=14`→`9..=16` | 上游無對應 PR → 自製 |

原設計檔 `design/fork-patch-dash-cmaf-bugfixes.md` 的 §3 施工流程（`patches/` + `git apply --check`）只適用於 D2/D4/D5 這類自製 patch；C/D1 不再需要。
