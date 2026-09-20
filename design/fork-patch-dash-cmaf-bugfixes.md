# 採用 fork 子集：DASH/CMAF 影片 + 小 bug fix 組（P1）

來源 fork：`https://git.ptr.moe/baalajimaestro/redlib`，commit `3f03e10`（2026-06-01，
「feat: add Tor onion routing, fingerprint gating, and DASH/CMAF support」）。
該 commit 的 parent `a4d36e9` 即 upstream `redlib-org/redlib` main（截至 2026-04-24）。
本地參考clone與 diff 存於 `redlib_docker/.tmp_fork_analysis/`（`fork/` repo + `cmp.json`）。

## 1. 採用範圍

### C. DASH/CMAF 影片格式支援
upstream `REGEX_URL_VIDEOS` 只認 `DASH_*.mp4`；Reddit 現大量回傳 `CMAF_*.mp4`，
CMAF 影片會掉成不 proxy 的直鏈。

| 檔案 | 改動 |
|------|------|
| `src/main.rs` | route `/vid/:id/:size` 拆為 `/vid/:id/dash/:size` + `/vid/:id/cmaf/:size` |
| `src/utils.rs` | `REGEX_URL_VIDEOS` 改 `(DASH|CMAF)`；`format_url` 的 `capture` 加 3-segment 分支（`/vid/{id}/{format}/{size}`） |

### D. 小 bug fix 組
| # | 檔案 | 改動 |
|---|------|------|
| D1 | `templates/post.html` | `single_thread` 加 `&& comments.len() > 0`（修 0 則留言時 panic） |
| D2 | `templates/post.html` + `static/style.css` | 兩個 `<form id="sort">` 重複 id → `class="comment_control_form"`；CSS 對應 selector 補 class |
| D3 | `templates/post.html`、`templates/comment.html`、`templates/utils.html`、`static/style.css` | overflow 組：`#comments` 容器、`blockquote.replies`→`div`、SVG 包 `<img>` 改直出 `<img>`、`.comment`/`.comment_body`/`.comment_data`/`#feed_list` 等 min-width/max-width/overflow 修正 |
| D4 | `static/highlighted.js` | 固定 `#commentQueryForms` scroll 改為通用 `location.hash` deep-link |
| D5 | `src/oauth.rs` | `android_version` 範圍 `9..=14` → `9..=16` |

### 明確不採用
- A：Tor onion routing（`src/reddit_urls.rs` 等）
- B：fingerprint gate（`src/fingerprint.rs`、`static/fingerprint.js` 等）
- E：Catppuccin 四主題
- F：`update_oauth_resources.sh`（APKMirror）、fork 對 upstream 本體 Dockerfile/`.github/workflows` 的改動、`0.36.0-yunyun` 版本號

## 2. 策略：拆成兩支 patch（C / D），build 時 `git apply`

C 與 D 檔案幾乎不相交，可獨立拆開、獨立驗證。**不可直接從 fork commit 摘 hunk**，
原因：

1. **C 的 `utils.rs` hunk 混入了 onion 網域**：`REGEX_URL_*` 全被加進
   `(?:reddit\.com|…onion)` 備選、`format_url` 先經 `reddit_urls::to_onion_url()` 正規化。
   摘出來後必須**手工改回 clearnet-only**：只保留 `(DASH|CMAF)` 與 3-segment capture，
   刪除所有 `.onion` 字串與 `reddit_urls` 呼叫。
2. `src/main.rs` 的兩條 route 本身就是 clearnet URL，可原樣採用。
3. D 的 hunk 自成一塊，基本可直接 `git apply`（style.css 11 個 hunk 全屬 overflow/
   排版組；若复审发现混入无关的 hover 视觉调整，剔除之）。
4. C/D 都不新增 Cargo 依賴 → `--locked` build 不受影響（fingerprint 的 hmac/sha2/cookie
   依賴屬於 B，不採用）。

## 3. 施工流程

1. **確認 upstream 漂移**：拉取 upstream main 目前 HEAD。
   - 若仍 = `a4d36e9`：在 scratch clone 直接 `git am` fork commit，再從工作樹切出 C/D 子集 diff。
   - 若已前進：同樣在 scratch clone 對**新的** main `git am`/cherry-pick fork commit 並解衝突
     （衝突點預測：`utils.rs` 的 `format_url`/regex 區段、`main.rs` route、`post.html`），
     再切子集。此後 patch 基底 = 當時 upstream main。
2. **切出 patch**：依 §2 手修後，產生兩檔存至 repo 根 `patches/`：
   - `patches/c-dash-cmaf.patch`
   - `patches/d-bugfixes.patch`
   patch 需附 `# 產生自 upstream main <sha> / fork commit 3f03e10` 標頭註解。
3. **Dockerfile 接線**（builder stage，clone 之後）：
   ```dockerfile
   COPY patches/ /tmp/patches/
   RUN git apply --check --whitespace=nowarn /tmp/patches/c-dash-cmaf.patch \
       && git apply --check --whitespace=nowarn /tmp/patches/d-bugfixes.patch \
       && git apply --whitespace=nowarn /tmp/patches/c-dash-cmaf.patch \
       && git apply --whitespace=nowarn /tmp/patches/d-bugfixes.patch
   ```
   `--check` 先驗讓 upstream 漂移時 build **明確失敗**（可預期、可修 patch），不會靜默編出舊行為。
   `.forgejo/workflows/build.yml` 觸發路徑加入 `patches/**`。
4. **本地測試 build**：`docker build --target builder -t redlib-test .`（確認 patch 套上、編譯過）。
5. **正式 build + push**：Forgejo 手動 dispatch（12 runner），`latest` + `<git-sha>`。
6. **線上驗證 checklist**：
   - C：找 CMAF 影片 post → `/vid/{id}/cmaf/{size}` 回 200；DASH 回歸 `/vid/{id}/dash/{size}`。
   - D1：開 0 則留言 post 的 permalink（single_thread），不 panic。
   - D2：留言頁 sort 下拉 + comment search 都正常；card/clean/compact 三種 layout 檢查
     留言區塊上方間距（見 §4 風險 2）。
   - D3：手機寬度下 `#feed_list` 不溢位；長 URL 留言可橫捲不撐破版面。
   - D4：`/r/<sub>/comments/<id>/<slug>#t1_<cid>` 錨點 scroll 正常。
7. **收尾**：TODO.md 該項移入「近期完成」、prune；更新 AGENTS.md「Redlib Source」節
   補一句「source = upstream main + `patches/` 內 patch（產生與更新方式見 design/）」；
   可刪 `.tmp_fork_analysis/`。

## 4. 風險 / Gotchas

1. **`/vid` route 路徑變更（breaking）**：舊 `/vid/{id}/{size}` 消失，改為
   `/vid/{id}/dash|cmaf/{size}`。站內連結由 `format_url` 產生新格式故無問題，但
   外部收藏/快取指向舊 proxy 路徑的連結會 404。屬可接受（上游日後若原生支援 CMAF，
   本 patch 應以相同思路重寫）。
2. **`#sort` id 移除使兩條上游 CSS 失效**：upstream `style.css` L1989-1990 有
   `#sort { margin-top: 49px }` 等規則；form 失去 `id="sort"` 後這些規則變成死碼，
   留言區塊上方間距可能改變（fork 自身也未修這兩行）。驗證 checklist 的 D2 一項
   就是為此；若間距異常，patch 內順手把這兩行改成 `.comment_control_form`。
3. **patch 會隨 upstream 漂移而失效**：`--check` 失敗即代表需重新走 §3 步驟 1-2
   （與既有「branch bump 後驗證 upstream 能編過」的紀律一致）。
4. `git apply` 的 context 行數：patch 以 `git diff`（3 行 context）產出，clone 用
   `--depth 1` 不影響 apply。
5. 授權：fork 與 upstream 同樣 AGPL-3.0，無新增授權問題。

## 5. 驗收標準

- `patches/` 兩檔可對當時 upstream main `git apply --check` 通過
- 正式映像跑過 §3 步驟 6 全部項目
- `docker exec` 或 `/settings` 頁行為與現行映像一致（未引入新 env 變數）
