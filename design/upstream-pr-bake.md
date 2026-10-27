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
| [#599](https://github.com/redlib-org/redlib/pull/599) | `26c02193`（pin 移到了 2026-10-27；原先分析時是 `0db637cd`） | 新增 `src/shreddit.rs`（791 行）+ `src/client.rs` 的 `shreddit_fragment()`：貼文改 `/by_id/t3_<id>.json`、**留言改抓 Reddit 前端自己的 `/svc/shreddit/comments/...` HTML fragment** 用 `scraper` 重建原 JSON 形狀；cookie session 輪替 + captcha 偵測；`Cargo.toml` 加 `scraper 0.29` 與 wreq `cookies` feature。**2026-10-27 改 pin 後多出的三支 commit**（`1d55e3e`/`a12eaf6`/`26c0219`）：`rdt` bot-check 的 302 追隨（最多 3 次，只准落在 `/svc/shreddit/`）+ 展開改用 `JoinSet`（不再批次柵欄）、留言裡的 `<shreddit-player>` 改原生 `<video>`（GIF autoplay/loop/muted）、**more-comments POST 補 `Origin`/`Referer`/`Sec-Fetch-*`**（Reddit edge 開始 403 缺這些的 POST）+ **shreddit 專用 client 改用桌面平台**（行動端每 fragment 只給 10 則，桌面 25 則） | 貼文頁留言恢復（`%2F` 繞行已被 Reddit 識破後唯一可行的上游方案）。⚠ **繞行、且不完整**：200 則上限、無 flair/awards、每頁 1–31 請求、subreddit 不驗證。⚠ **只吃 IP：出口是機房 ASN（Oracle/Hetzner/Vultr…）的實例，`/svc/shreddit/` 從第一個 fragment 就 403，換 pin 也不會修好** —— 詳 §8.13（2026-10-27 o3/123 定因）。詳 §8.12 |
| [#592](https://github.com/redlib-org/redlib/pull/592) | `1e9515eab8d0` | `src/client.rs`：`encode_thread_route()` 把 `/r/<sub>` 與 `comments` 之間那**一個** slash 編碼成 `%2f`（放進 `json()` 入口，涵蓋所有呼叫者）；另加 `non_json_response_error()` 把 403 區塊頁報成「Reddit blocked this request (403 Forbidden)…」而非 parse error。附 5 個純函式測試 | **貼文頁恢復可用**（此前所有實例的 `/r/x/comments/<id>/…` 全數 403 → 前端 `Failed to parse page JSON data: expected value at line 1 column 1`）。⚠ **這是繞行，不是根治**，見 §8.8。
> **2026-10-22 退役**：上游 v0.40.0 以直接 commit `0a3e9cd fix: encode anonymous comments request paths` 實作等效 `%2f` 繞行（同碰 `src/client.rs`）。#592 作為 **PR 從未合併**，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故已從 `redlib-prs.txt` 移除；thread-403 現由上游 `0a3e9cd` 供應。見 §8.8。
> **2026-10-27 複核（使用者問「#592 後來被關了，我們要做什麼嗎」）→ 答案：不用做任何事。**
> - PR 已由維護者 `sigaloid` 在 **2026-10-21T22:57Z 直接 close（未 merge）**，`mergeable=false`、無 review、討論區有人嗆 "AI slop"。它的兩支 commit（`b920292d`/`1e9515ea`）以 `git cherry -v origin/main pr592` 檢查**仍全是 `+`**（從未以 patch-equivalent 進 main）→ 我們的「它沒被上游 merge、改用上游等效 commit」判定到現在都正確。
> - **新實測把 `0a3e9cd` 那招也正式判死**（之前只是推論）：用 `redlib-prs.txt` **去掉 #599** 建的對照映像（= main + 其餘 5 支，保留 `0a3e9cd` 的 `%2F` 編碼）在**出口好的 123 與被封的 o3 上都拿不到留言**：4 條貼文全 404 / `Failed to parse page JSON data: expected value at line 1 column 1` / 0 則留言。**結論：#599 目前是 load-bearing，不能因為它是 workaround 就丟掉**（詳 §7、§8.14）。 |

**merge 順序 = `redlib-prs.txt` 檔內順序**（549 → 542 → 521 → 560 → 539 → 599）。六支檔案重疊極少（549 與 560 同碰 `src/main.rs` 但不同區塊），實測 `--no-ff` 全 clean；2026-10-23 以 `git merge --no-ff` 驗證過 **#599 放最後與放第一個都是 six-way clean**（#599 只碰 `client.rs`/`post.rs`/`lib.rs`/`shreddit.rs`/`Cargo.*`，與其餘五支零重疊），本地 `docker build` 亦 exit 0（`--locked` 未報 lock 不一致）。
> 2026-10-27 重新驗證：#599 head 從 `0db637cd` 推到 `26c02193`（+3 commits，只碰 `src/client.rs` 與 `src/shreddit.rs`，**`Cargo.toml`/`Cargo.lock` 零變化** → 相依數與映像體積不變），以 `26c02193` 為底依序 `--no-ff` 併入其餘五支 **全 clean**。
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
| [#603](https://github.com/redlib-org/redlib/pull/603) `6cd8366a`（2026-10-24 開，**未 merge、0 review**） | 留言改走 Reddit 的 Android `PostComments` **persisted GraphQL**（`gql-fed.reddit.com`，hash `314f29c2…`），**取代**（不是補上）shreddit 那條路：新檔 `src/gql.rs` +635、`post.rs` 只改那行 fetch（`json(path)` → `gql::thread(path)`）、`lib.rs`/`utils.rs`/`templates/{post,comment}.html` 各 1–4 行；**完全不碰 `Cargo.toml`/`Cargo.lock`**（零新相依） | **2026-10-27 已實測評估，判定：現在不 bake**（§8.14）。要點：它跟 #599 **互斥**（同一行 fetch，兩支同時 bake 時 `src/post.rs` 與 `templates/post.html` 都衝突，且不管誰先誰後都衝突）；在出口可用的 123 上它**能動而且比 #599 快 2.7–4×**、並用 `cursor` 真的突破 200 則上限（下一頁 200/58,810 B/51 則/0.36s），但**在 o3（機房 ASN）留言 0 則**、錯誤頁與「沒有 #599」的對照映像**逐位元組相同** → 救不了我們真正壞掉的那台；且它依賴 Reddit **未文件化的 Android persisted-query hash**（與 #599 同一脆度等級，hash 一輪替就又壞）。重啟評估的觸發條件見 §8.14。

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
| `.build/apply_redlib_prs.sh` | 在 clone 好的 redlib 樹上依清單 `git fetch pull/<n>/head` + `git merge --no-ff`；head 漂移會 warn，衝突直接失敗。⚠ **列在 `redlib-prs.txt` 的 SHA 預設只是「漂移警示」，不是版本鎖定**：建置永遠拿 PR 的當前 head（2026-10-27 親身踩到：用舊 pin 做 A/B，結果兩邊都 build 到新 head，只差一行 `warning:`）。要真的重現過去某一組 bake 組合，用 `--at-listed-sha`（它會 `fetch pull/<n>/merge` 再取 PR 側 parent，因為 `refs/pull/<n>/head` 永遠只有最新 head）；實測能解析 `0db637cd` 並重建出 719 行的 `src/shreddit.rs` |
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
  - [ ] 請求放大成本：本地**冷 3.07s / 熱 0.019s**（listing 0.74s）→ 上線後看真實流量下的延遲與 rate-limit 訊息頻率
  - [ ] 留言缺 author flair / awards（外观退步，非功能错误）
- [x] **#599 pin bump 2026-10-27（`0db637cd` → `26c02193`）**（本地 build + 出口可用機器上的容器 A/B，全部跑完）：
  - [x] 本地 `docker build` exit 0，log 出現 6 行 `Merging PR #<n>` 且**無 `warning:`**（pin 已對齊 head，不再報 `head moved`）
  - [x] **真正的對照組要用 `--at-listed-sha` 才建得出來**：直接拿舊 pin 跑 `docker build` 會**靜默 build 到新 head**
        （兩邊 image ID 完全相同 = `1f386abe78a8`，只有 `warning:` 一行線索）。用
        `docker build --build-arg BAKE_ARGS=--at-listed-sha` 才產出 pin 在 `0db637cd` 的映像（ID `9f8a10cb6e87`）。
  - [x] **A/B（出口可用機器，同一 sub、同一刻、同一個 3.8k 留言的討論串）**：
        舊 head → 200 / 237,891 B / 3.10s / 229 個留言塊 / 73 個 `More replies`；
        新 head → 200 / 218,557 B / 2.93s / 211 個留言塊 / 70 個 `More replies`；兩邊 log 皆 0 WARN、0 panic。
        → **在我們的環境重現不出「展開全滅」**（上游作者是在他的 client 被隨機指派到 Chrome 模擬時看到的；
        我們的 client profile 也是隨機 `[Chrome145, Firefox147]`，這次兩邊都落到能用的那一側）。
        所以 `26c02193` 那三支 commit 對我們是**低風險、但未能本地證明療效**的更新（照 §0 的規矩如實記）。
  - [x] **行動端/桌面差異是真實存在的**（從出口可用機器直打 Reddit）：同一個 fragment，
        桌面 UA → 200 / 614,871 B / 132 個 `<shreddit-comment>`；Android UA → 200 / 266,498 B / 43 個。
        舊 head 的 shreddit 請求**共用主 client**，而主 client 的平台是啟動時隨機 `[Android, Windows]`
        （≈50% 機率落到行動端 → 每頁少一半素材，且**每次重啟重新抽一次**，watchtower 每 30 秒掃一次、每天重啟都會 reshuffle）；
        新 head 有**專用的 `SHREDDIT_CLIENT`，平台固定 Windows** → 不再靠擲硬幣。這是這次 pin bump 最硬的實測理由。
  - [x] `more comments` POST 的 `Origin`/`Referer` 規則**本地無法驗證**：不帶 cursor 的 POST 一律 405
        （18 B），而 cursor 只能從已渲染的頁面裡取得 → 又一個 §3 那類「裸 curl 無辨識力」的假陰性陷阱。
        上游作者的觀察是 Chrome 模擬被擋、Firefox 透過（機率性）。
  - [x] 新 head 其他 §7 項目：留言 permalink `…/<cid>/?context=3` → 200 / 57.5 KB / 49 則留言、目標留言在頁上；
        三種留言排序塊數各不同（confidence 216 / new 220 / top 280）；不存在的 post → 404 +
        `Reddit error 404 "null": "Not Found"`（不是 parse error）；錯的 sub + 對的 post id → **仍然 200 並渲染別篇文章**
        （§8.12 的缺陷在新 pin 依舊存在）；冷 2.91s / 熱 0.013s；panic 0。
  - [x] **第二輪 A/B（2026-10-27，三映像、兩台機器，答「#603 要不要 bake」）**：
        對照 = 正式 `:24f7dce`（含 #599）、實驗 A = **去掉 #599**（只留其餘 5 支，仍含上游 `0a3e9cd` 的 `%2F` 繞行）、
        實驗 B = **把 #599 換成 #603**（`gql::thread()`）。三支配方都是同一條 bake 鏈（`apply_redlib_prs.sh`）產出，
        o3 上的 B/A 還在 o3 本機 arm64 原生編譯（跨架構 binary 不能混用）。
        結果（同一時刻、同一 4 條貼文，`class="comment"` 計數／bytes／時間）：
        | 貼文 | 含 #599（正式） | **不含 #599** | 換成 #603 |
        |---|---|---|---|
        | `/r/comics/…1xgpbes` | 200 / 101,276 B / 2.42s / **79** 則 | **404 / 6,663 B / 0 則**（parse error） | 200 / 95,619 B / **1.02s** / **80** 則 |
        | `/r/thisecommercelife/…1wakyfh` | 200 / 27,946 B / 0.90s / 8 | 404 / 6,707 B / 0 | 200 / 27,012 B / 0.66s / 8 |
        | `/r/thisecommercelife/…1wn668j` | 200 / 36,139 B / 0.86s / 12 | 404 / 6,707 B / 0 | 200 / 30,543 B / 0.98s / 12 |
        | `/r/mildlyinfuriating/…1xg1a61`（大） | 200 / 262,192 B / 3.06s / **240** 則 / 112 個未展開 | 404 / 6,731 B / 0 | 200 / 240,936 B / **1.13s** / **200** 則 / 148 個未展開 |
        → **兩個結論**：(1) **不含 #599 的映像在所有貼文、兩台機器上都拿不到留言**（404 + parse error，錯誤頁位元組
        6,663/6,707/6,707/6,731）→ 上游 `0a3e9cd` 的 `%2F` 繞行在**住宅出口也一樣死了**，#599 是 load-bearing；
        (2) #603 在出口好的機器上**可用且快 2.7–4×**，另外三種留言排序都吃得到（bytes 242,354/194,960/255,720 各不相同、
        時間 0.80/0.71/0.73s），`class="deeper_replies"` 的 `cursor` 連結**真的突破 200 則上限**（下一頁 200 / 58,810 B / 51 則 / 0.36s）。
  - [x] **o3（機房 ASN）上同一輪的結論**：正式映像（含 #599）404 + `Reddit returned 403 Forbidden \| /svc/shreddit/comments/r/…`（0 則）；
        **換成 #603 後 404、0 則留言，且錯誤頁與「不含 #599」的對照映像逐位元組相同**（6,663/6,707/6,707/6,731）；
        列表 `/r/popular` 三支配方都 200 / 59,929 B / 25 篇（**只有留言壞，本體沒壞**）。
        → 判定：**#603 救不了被 Reddit 擋出口 IP 的實例**（§8.13 那一層跟用哪條留言路徑無關）。
        ⚠ 尚**未查明** o3 上 #603 死在哪一段（`/by_id` 那段在 #599 映像裡是成功的，所以可能是 `gql-fed.reddit.com` 那段；
        兩條候選與查法見 §8.14）。負 control（不存在的 post）在 #599/#603 兩邊都是 `Reddit error 404 "null": "Not Found" \| /by_id/t3_zzzzzzz.json?raw…` → 正確。
  - [ ] 本輪**未補到**的項目：0 則留言的 post（在用的 subreddit 列表裡找不到素材）、quarantined sub、
        留言媒體的 `<video>` 改造（抓到的那个討論串沒有留言媒體）。
  - [ ] 已知**仍未修**（不在這次 pin bump 範圍）：留言圖片 overflow 容器（Sparronator9999 2026-10-27T07:42Z 回報，
        `26c02193` 之後零 commit）、200 則上限（大討論串照舊留 70–80 個 `More replies` 殘根）、§8.12 其他缺口。
        ⚠ 機房出口的 o3 這次**沒有用新 pin 重測**：它壞在出口 IP（§8.13），換 pin 預期不會改變結局。
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

12. **#599（shreddit fragment）——貼文頁留言的目前唯一可行上游方案，但它不是根治，也不完整**（2026-10-23 bake）：
    - **背景**：Reddit 把匿名 client 的 comments API 全數 403，**连帶 `%2F` 编码繞行也被破**（上游 v0.40.0 的 `0a3e9cd` 失效）。
      定因方式：線上 `/`、`/r/popular` = 200，貼文頁 = 404 + parse error（`…/.json?&raw_json=1`）→ 仍是**按路徑**的封鎖。
      本機 curl 對 Reddit 所有端點（含 `by_id`、`/svc/shreddit/`）一律 403 同一份 block page → 對本機 IP 而言裸 curl **無區辨力**（playbook 假陰性）。
    - **機制**：貼文走 `/by_id/t3_<id>.json`；留言走 `www.reddit.com/svc/shreddit/comments/r/<sub>/t3_<id>[/t1_<cid>]`，
      用 `scraper` 把 `<shreddit-comment>` 重建為原 JSON 形狀（`parse_comments`/模板不改）；「More replies」以 `more-comments` POST + 隱藏 `cursor`
      做 BFS，上限 `CRAWL_LIMITS = {200 留言, 30 expansions, 10 併發}`；cache 30s；反限流靠**自己的 cookie jar**（wreq `cookies`），
      `x-ratelimit-remaining < 20` / 429 / 比對到 captcha 頁面標題字串就輪替 session 再重試一次。
    - **分級：繞行（workaround），不是 root fix**。re-break 觸發條件：（a）Reddit 關掉或改格式 `/svc/shreddit/` fragment；
      （b）captcha 頁的 title 字串改寫（它靠字面比對判 captcha，一改就會把 challenge 頁當留言內容解析）；（c）`by_id/t3_<id>.json` 也被封。
    - **observable（下次要 grep 的）**：`Reddit returned <status> | /svc/shreddit/...`（(a)/(c)）、
      `Reddit is rate limiting comment requests. Try refreshing in a few seconds.`（配額耗盡）、
      `Refusing to fetch non-shreddit path`（路徑守衛）、舊的 `Failed to parse page JSON data: expected value at line 1 column 1`（`by_id` 也被封）。
    - **已知不完整（本機實測）**：留言 200 則上限（大讨論串剩 93–106 個未展開殘根）；留言無 author flair/awards；
      每個未 cache 的貼文頁 1–31 個請求（**冷 3.07s / 熱 0.019s**，listing 0.74s）；`SHREDDIT_SESSION` 是 process-global
      → 同實例所有訪客共用一份配額；**subreddit 名稱不再被驗證**（錯 sub + 對 post id 回 200 並渲染別篇文章）；
      quarantined sub 未測；映像 13.5MB → 14.8MB（新增 25 個 crate）。
    - **信任面**：留言 `body_html` 改由 fragment 的 `inner_html()` 產生，而 redlib 對 `body_html` 是 `|safe` 渲染且**不做 sanitize**（無 ammonia）
      → 信任對象從「Reddit API 的 body_html」變成「Reddit 前端 fragment 的渲染結果」。
    - **品質風險**：上游 PR 為 **AI 生成、0 review、0 check runs**（head `0db637cd` 沒被任何 CI 编譯過）；
      我們的 `--locked` 本地 build 已通过（PR 自帶的 `Cargo.lock` 自洽，含 `cookie` 進 wreq deps + 25 個新 package），
      但 **不保證未來上游 main 漂移後 lock 仍自洽** → head 漂移動會 warn（`redlib-prs.txt` 已 pin）。
    - **退出策略**：若 Reddit 封掉 shreddit 或 #599 被 force-push 成不能用，從 `redlib-prs.txt` 移除該行即可（`client.rs`/`post.rs` 回到上游 v0.40.0 形態）；
      屆时貼文頁會回到 parse error，**不要重啟容器當解法**。

13. **出口 IP 信譽是獨立於 code 的失敗層：同一個 digest，兩台實例結果相反**（2026-10-27 o3 vs 123 定因）：
    - 兩台都是**同一個 manifest digest** `sha256:73900bee…8932e`（= `ac3f175` 那次 CI，含 bake #599）：
      o3（OCI VPS，出口 `<o3 公網 IP>`，**AS31898 Oracle**，東京；跑 `codeberg.org/lawlietr/redlib:latest`，arm64）
      與 123（內網，出口 （她的自宅公網 IP，值在 private repo），**AS4780 DUI**，台北 ADSL；跑 `ghcr.io/lawlietr/redlib:latest`，amd64）。
      兩台的 `RepoDigests` 相同 → **變數不是 code**。
    - 結果：**123** 貼文頁 200 / 162 KB / 153 則留言、log 零錯誤；**o3** 貼文頁 404 / 6.5 KB，頁面寫
      `Reddit returned 403 Forbidden | /svc/shreddit/comments/r/interesting/t3_1xgj…`（列表 `/r/popular` 仍是 200）。
    - 判讀鏈：貼文本體那步（`/by_id/t3_<id>.json`，走 OAuth token）在 o3 **成功** → post 有渲染；死在留言那步
      （`/svc/shreddit/`，**無 token 可用**，只能吃 IP 信譽）。而那個 `| /svc/shreddit/…` 路徑字尾**只有 bake #599
      的 code 會產生** → 看到它就等於證明該實例已在跑 #599，換 pin（含 #599 的新 head）**不會修好它**。
    - 判別指令與完整表格在 `design/error-triage-playbook.md` §4.2（裸 curl 對兩個 IP 都 403，無辨識力；
      只有「瀏覽器級 headers + HTTP/2」能把差異暴露出來：住宅 200 / 915 KB，機房 403 / 同一份 190240 B block page）。
    - **掛 Cloudflare CDN（橘雲）不會改變這件事**：橘雲代理的是**進向**（訪客 → CF edge → origin），遮的是訪客的
      IP 與瀏覽器指紋，保護對象是 origin（DDoS、隱源 IP）。Reddit 看到的只有**出向**那段：由該機器自己的公網 IP
      直接發起的 `redlib → www.reddit.com`，這段不經過 CF，CF 不會出現在路徑上，也不會改寫我們這端的 TLS/HTTP2 指紋。
      所以「我們的 web 有掛 CF → Reddit 會指紋識別到 o3 有 CDN」這個擔心不存在：Reddit 只看到 `<o3 公網 IP>`；
      而 redlib 的 wreq 指紋已是瀏覽器級、列表也拿到 200，卻照樣在 `/svc/shreddit/` 吃 403 → **IP 信譽問題，不是指紋問題**。
      （CF Tunnel 同樣只處理進向；要把出口變成 CF 的 ASN 得在主機跑 WARP 之類出口代理，但 Reddit 對 Cloudflare ASN
      照樣擋——不是可用解方。）
    - **redlib 沒有出口代理設定**：上游只有**進向**的媒體 proxy route（`main.rs` 的 `/img`、`/thumb`、`/hls`、`/vid`…），
      `src/` 內沒有任何 egress proxy 的 env 或代碼（2026-10-27 以 `git grep -i proxy` 在含 #599 的樹上確認）。
      → 「讓壞 IP 的實例走好的出口」只能做在**容器/主機層的 L3–L4 tunnel**（o3 與 123 兩台都看到 ZeroTier 的痕跡：
      o3 有 `zerotier` 容器目錄與 <o3 的 ZT IP> 介面、123 裝了 `zerotier-one`），不能指望 redlib 的 env 或 patch。
      Tor 出口不是選項（123 上的 `tor-9050`/`tor_s` 不要拿來當地點：Reddit 封 Tor exit 比封機房更兇）。
    - **退出策略**：把該實例的 redlib 搬到有住宅出口的機器（123 已驗證可用），或接受該實例只有列表可用
      （貼文連結導到可用實例）。**不要**用重新編譯／換 env／重啟容器當解法——那是浪費時間。
### 8.14 #603（GraphQL 留言）評估：判定「現在不 bake」，以及重啟評估的三個觸發條件（2026-10-27）

- **做什麼的那支**：`fxmfxmfx` 2026-10-24 開，head `6cd8366a`，2 commits，+651/−4、7 檔，`mergeable=true`、**0 review**。
  新檔 `src/gql.rs`（+635）把 Reddit Android App 的 **persisted GraphQL operation `PostComments`**（`https://gql-fed.reddit.com/`，
  `sha256Hash = 314f29c2494f…`，hash 抄自第三方的 `Amqx/reddit-gql`）轉成 redlib 原有的兩段 `Listing` 形狀，
  自寫 RTJSON→HTML renderer（`htmlescape` 逃脫、URL 過濾）、`COMMENT_COUNT=200`、`MAX_DEPTH=10`、`cursor` 分頁（分頁連結在
  `templates/post.html` 的 `class="deeper_replies"`）。貼文本體仍走 `client::json("/by_id/t3_<id>.json?raw_json=1")`，
  OAuth headers 是從 `OAUTH_CLIENT.load_full().headers_map` 複用（所以 GraphQL 那段**帶 token**，與 §8.13 裡
  「留言那條沒 token 可用」的前提**不同**）。作者自述：45 個離線測試（含 9 個 GraphQL）、`cargo fmt`/`clippy -D warnings`
  乾淨、在自己的 Debian LXC 上線上驗證過（200+186 則、巢狀 6 則），並已上生產。
- **為什麼不能跟 #599 併存**：兩支改的是 `src/post.rs` 的**同一行**（`json(path)` vs `gql::thread(path)` vs #599 的 `by_id`+`shreddit::comments`）。
  實測 merge probe：`main + 599` 再 merge 603 → `src/post.rs`、`templates/post.html` 衝突；反過來先 603 再 599 同樣衝突。
  **去掉 599** 只 bake 603 時，只剩 `templates/post.html` 一處衝突（#542 的 `{% if single_thread && comments.len() > 0 %}`
  vs #603 的 `!comments.is_empty()` — 語意相同，取一邊即可），`src/post.rs` 自動合併。**換手（599→603）在 git 上是可行的**，
  但這就不是「多一個 option」而是**兩套留言渲染路徑二選一**。
- **為什麼現在不 bake**（三條，按重要性）：
  1. **救不了壞的那台**：o3 上換成 #603 仍是 404 / 0 則留言，而且錯誤頁與「不含 #599」的對照映像**逐位元組相同**
     （6,663 / 6,707 / 6,707 / 6,731）。§8.13 那一層（出口 IP 信譽）不會因為換留言來源而消失。
     ⚠ **未查明 o3 上死在哪一段**，兩條候選：(a) `gql-fed.reddit.com` 那段被機房 IP 擋（若如此，#603 對被封實例**仍有可能**比
     #599 好，因為它帶 token → 這條一定要在重新考慮換手前先測掉）；(b) `/by_id` 那段在 #603 的 tree 裡反而失敗（同一台 o3 上
     #599 映像的 `/by_id` 是**成功**的，所以這條看起來不像）。查法（下次要做時）：在 o3 跑 #603 容器，
     `docker logs` 看那行 `ERROR redlib::utils > Error page rendered: …` 的**完整訊息**（#603 的 GraphQL 失敗會回
     `Reddit comments request returned <status>` / `Reddit returned an invalid comments response` / `Reddit comments API error: […]`，
     而 `client::json()` 失敗會是 `Failed to parse page JSON data: …` 或 `Reddit returned <status> | <path>`）——
     看到前三種就是 (a)，看到後兩者就是 (b)。**這是最後一次用「猜」的，別在沒讀到那行 log 之前決定換手。**
  2. **脆度同級、但少一條退路**：依賴 Reddit **未文件化的 persisted-query hash**（外加 `PostComments` 的欄位形狀）。
     Reddit 一輪替 hash 或改 schema，留言就整批壞，而且错误會长得像「上游改了」而不是「我們依賴的東西變了」。
     #599 依賴的是 Reddit 給登出訪客的 HTML fragment（也是未文件化），但兩者**不同源**，所以「只留一套」= 失去互為備援的條件。
  3. **每頁留言數變少**：大討論串 240 → 200（#603 每頁硬性 200 + 10 層），未展開的 `More replies` 反而變多（112 → 148）。
     換來的是 2.7–4× 的速度與真正可用的 `cursor` 下一頁（這是 #599 **做不到**的：#599 的 200 則上限是 crawl 上限，沒有分頁連結）。
- **什麼情況下重啟評估（三個觸發條件，任一成立就重測）**：
  1. **#599 坏**（Reddit 改掉 fragment HTML 結構 / `rdt` bot-check 升級 / 對 shreddit 端的 IP+UA 規則收緊）→ #603 立刻從「觀望」變「候選」；
  2. **我們要突破 200 則**（使用者回報大討論串看不完、或我們要 `?cursor=` 分頁這種 UX）→ #603 是唯一有分頁的上游方案；
  3. **上游把 #603 merge 進 main**（或 merge #599 後要求二選一）→ 屆時由 upstream 決定取捨，我們只跟 pin。
  另外：如果決定換手，**先**在 o3 上把上面那條 log 讀出來（條件 1 的前置），並在 123 上做標準雙映像 A/B
  （`design/error-triage-playbook.md` §3），兩邊都過才改 `redlib-prs.txt`。
- **相關的其它 PR（避免重複評估）**：#601（`xevxx`，用 logged-out comments API 修 thread 載入）**2026-10-23 已 close 未 merge**；
  #598（update-check TypeError）與此無關。2026-10-27 的 open PR 全清單（51 支）中，與「匿名留言」相關的只有 #599 與 #603。
  ⚠ 顺帶記錄：#605（`rss 2.1.2` 修 quick-xml DoS 兩條 RUSTSEC）**2026-10-27 close 未 merge**，但上游 main 的 `Cargo.lock`
  已經是 `rss 2.1.2 / atom_syndication 0.12.10 / quick-xml 0.41.0`（直接 commit 進 main）→ **我們的映像不需要動作**；
  另外上游 main 的 lock **沒有 `scraper`**，它是 #599 帶進來的（+26 crates）→ 換手到 #603 反而會**減掉**這 26 個相依（零新相依）。

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
