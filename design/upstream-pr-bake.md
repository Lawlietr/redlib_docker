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
| [#560](https://github.com/redlib-org/redlib/pull/560) | `7a284d30` | 新增 `/u/:name/s/:id` 分享連結處理 | 使用者文章分享連結不再 404 |
| [#539](https://github.com/redlib-org/redlib/pull/539) | `514202ad` | `templates/utils.html` 移除 `<svg><image>` 包裝，改直出 `<img loading="lazy">` | 圖片 lazy-load；同時覆蓋原 fork patch D3 的 SVG 部分 |
| [#592](https://github.com/redlib-org/redlib/pull/592) | `1e9515eab8d0` | `src/client.rs`：`encode_thread_route()` 把 `/r/<sub>` 與 `comments` 之間那**一個** slash 編碼成 `%2f`（放進 `json()` 入口，涵蓋所有呼叫者）；另加 `non_json_response_error()` 把 403 區塊頁報成「Reddit blocked this request (403 Forbidden)…」而非 parse error。附 5 個純函式測試 | **貼文頁恢復可用**（此前所有實例的 `/r/x/comments/<id>/…` 全數 403 → 前端 `Failed to parse page JSON data: expected value at line 1 column 1`）。⚠ **這是繞行，不是根治**，見 §8.8 |

**merge 順序 = `redlib-prs.txt` 檔內順序**（549 → 542 → 521 → 560 → 539 → 592）。六支檔案重疊極少（549、592 同碰 `src/client.rs` 但不同區塊；549 與 560 同碰 `src/main.rs` 但不同區塊），實測 `--no-ff` 全 clean（2026-10-21 以「五支 Tier 1 之上再併 592」的順序實測）。

> 不用 `-X ours`：舊 bake 鏈用 `-X ours` 是因為那些 PR 基於 pre-wreq 的 main；現在五支都 clean，`-X ours` 只會**靜默吃掉 upstream 改動**（正是 pr509 那棵樹悄悄留著 pre-wreq `client.rs` 的教訓）。

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
- [x] `docker build -t redlib:local-test .` 成功；log 中出現 6 行 `Merging PR #<n> -> <sha>` 且無 `warning:`（2026-10-21：本地與兩條 CI 皆是 `Baked 6 PR(s)`）
- [x] `docker run --rm --entrypoint /redlib redlib:local-test --help` 可執行（2026-10-21 以更強的證據取代：published 映像 `codeberg.org/lawlietr/redlib:15cc3c1` 實際起服務並回應請求）
- [ ] 靜態確認 baked 樹：`CMAF`、`rich:video`、`/vid/:id/:prefix/:size`、`comments.len() > 0`、`setting(&req, "post_sort")`、`/u/:name/s/:id` 都在

**線上（部署後）**
- [ ] CMAF 影片 post → `/vid/{id}/cmaf/{size}` 200；DASH → `/vid/{id}/dash/{size}` 200
- [ ] 0 則留言 post 的 permalink 不 panic
- [ ] 未存過設定的新訪客：`REDLIB_DEFAULT_POST_SORT` 生效
- [ ] `/u/<user>/s/<postid>` 分享連結正確導向
- [ ] 文章圖片帶 `loading="lazy"`，版面不破（#539 改了 post media 的 DOM 結構）
- [x] 貼文頁 `/r/<sub>/comments/<id>/<slug>/` 200 且留言正常（#592）；對照組（不含 #592 的舊映像）應精確重現 `Failed to parse page JSON data: expected value at line 1 column 1`（2026-10-21 雙映像 A/B 兩半都成立）
- [x] 不存在的 post / sub 仍回**正確的 Reddit 404/400 錯誤頁**，不是 parse error（#592 第二個 commit 的錯誤分級）
- [x] 列表端點未受 #592 影響：`/r/<sub>`、`/r/popular`、`/r/all`、`/search`、`/u/<user>`、`/r/<sub>/duplicates/<id>`（2026-10-21 全部 200）
- [ ] 舊 `/vid/{id}/{size}` 連結 → 404（**已知 breaking**，見 §8）

> 2026-10-21：**上線確認已完成於兩個架構**——amd64 與 arm64 的 container 都已架起來、實測兩邊都正常運行（`codeberg.org/lawlietr/redlib:latest` = `15cc3c1`，同一個 manifest list）。
> 上面仍標 `[ ]` 的項目是**逐功能**的線上確認（影片 proxy 新格式、0 則留言 panic、預設 post sort、分享連結、lazy-load、舊 `/vid` 連結 404），
> 這些需要對應的貼文/設定才能驗，跟「容器能不能跑」不同層次，別因為架構實測通過就當成已核。

## 8. 風險 / Gotchas

1. **`/vid` 路徑變更（breaking）**：`/vid/{id}/{size}` → `/vid/{id}/dash|cmaf/{size}`。站內連結由 `format_url` 產生新格式，站內無問題；外部收藏/快取的舊 proxy 連結會 404。
2. **#521 改變 post_sort 來源**：從 cookie 直讀改成 `setting()`（prefs 合成後的結果）。需回歸 `/r/x/?sort=` 與「未存設定的新訪客」兩條路徑。
3. **PR head 會動**：open PR 可能被 force-push。`redlib-prs.txt` 的 SHA 欄只用於**警示**，build 仍抓最新 head；要完全重現某次映像，用 registry 的 `<git-sha>` tag，或把 `REDLIB_BRANCH` 釘死 + 手動 fetch 指定 SHA。
4. **`--depth 300`**：shallow clone 必須夠深才能找到舊 PR 的 merge base（目前 PR 的 merge base 距 main HEAD 約 8 個 commit，300 很寬）。若 `git merge` 出現「unrelated histories」類錯誤 → 加大 depth。
5. **兩條 build 路徑要同步**：`Dockerfile`（glibc 靜態，amd64）與 `.forgejo` 腳本（musl 交叉編譯，amd64+arm64）都必須讀同一份 `redlib-prs.txt`，否則 CI 映像與本地映像內容不同。
6. **clean merge ≠ 語意正確**：六支裡只有 #592 碰 `src/client.rs`（其餘改動落在模板、`main.rs`、`subreddit.rs`、`utils.rs`），都沒碰 `Cargo.lock`，風險低，但仍需一次真實編譯（§7）與一次雙映像 A/B（`design/error-triage-playbook.md` §3）才算數。
7. **參數路徑**：`apply_redlib_prs.sh` 會先 `cd` 進 source 目錄才讀 PR 檔，所以兩個參數一律先 `realpath` 解析。
   `.forgejo` 那條路徑傳的是**相對**路徑（`redlib-src` / `redlib-prs.txt`），Dockerfile 傳**絕對**路徑 —— 兩種都要測
   （2026-10-07 就是相對路徑在 12 runner 上炸 `redlib-prs.txt: No such file or directory`）。
8. **#592 是繞行（workaround），不是根治**：它只是把 slash 編碼成 `%2f` 去**避開 Reddit 邊緣節點的路徑匹配規則**，Reddit 的政策方向是把這類資料推向登入後才能取用。再壞的觸發條件與處置：
   - Reddit 開始 normalise 該編碼（把 `%2f` 還原成 `/` 再比對路徑）→ 貼文頁再度全數失效。屆時**不會**再出現誤導性的 parse error，而是 `Reddit blocked this request (403 Forbidden): Reddit now requires a logged-in session for this endpoint | <path>`（來自 `client.rs` 的 `non_json_response_error()`）——**下次使用者回報先 grep 這個字串**，就能直接判定「舊繞行失效」而不是新故障。
   - 上游同一事件還標明**不在這支 PR 範圍**的鄰居問題：首頁 `hot.json` 的 parse error（上游 #589）、Anubis PoW 擋程式化存取（上游 #567）。本機 2026-10-21 實測這兩個端點仍正常，但別误以為一併修好。
   - 上游 PR 未合併（無 review、1 位參與者、1 個 👎），因此 head 可能被 force-push：`redlib-prs.txt` 的 SHA 一漂移就要重跑 `design/error-triage-playbook.md` 的 A/B，不能只信 build 成功。

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
