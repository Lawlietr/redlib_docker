# 線上錯誤溯源 SOP：從使用者回報到 bake 決策

> 起源事件：2026-10-21，使用者回報「點貼文就出現
> `Failed to parse page JSON data: expected value at line 1 column 1 |
> /r/SteamdeckGames/comments/1xautuo/…/.json?&sort=confidence&raw_json=1`」。
> 上游 issue #591 / PR #592 對應此症狀。**本檔記錄的是流程，不是該事件的答案**
> （該事件的 tier 判定與實測資料一律寫進 `design/upstream-pr-bake.md` 的 Tier 表）。

## 0. 核心原則（這事件教了三件事）

1. **redlib 的錯誤訊息通常是「症狀」而非「原因」**。
   `Failed to parse page JSON data` 只說明 Reddit 回來的 body 不是 JSON，
   真正原因可能是 403 區塊頁、5xx、rate limit、或路由被移除。
   → 永遠先定位「哪一個 upstream HTTP 呼叫失敗」，再去猜原因。
2. **「重啟容器就好」的直覺不可靠，要先實測**。
   該事件的重點是 Reddit 的封鎖是**路徑規則**（同一 token、同一 IP、同一秒：
   `/r/x/hot.json` 200、`/r/x/comments/<id>/.json` 403），不是 token/指紋問題。
   換 token（重啟）自然無效。任何「換一輪就好的直覺」都要先用同一 token 對兩個端點做對照。
3. **不能只讀上游 PR 的描述就下結論**。PR 作者聲明的技術假設（例：把某個 slash percent-encode
   就能繞過匹配）必須在**我們自己的環境**重現；上游作者的 IP／網路與我們不同。
   唯一可信的判定是**含／不含該 PR 的兩份映像，在同一台機器、同一時刻跑同一個 URL**。

## 1. 步驟一：把錯誤訊息映射到 redlib 的呼叫點

```bash
# 上游 clone（淺即可，只要读得懂源碼）
git clone --depth 1 https://github.com/redlib-org/redlib.git /tmp/redlib-triage
# 錯誤訊息字串在源碼裡的產生點
grep -rn "Failed to parse page JSON\|Reddit is having issues\|Reddit error" /tmp/redlib-triage/src
```

- 讀該 callsite 的上下文，找出它屬於哪個函式（`client.rs` 的 `json()`／`request()`／
  `reddit_get()`／`reddit_short_head()`）與哪些 route handler 會走到它。
- 從 URL 本身也能反推：query 带 `raw_json=1` 的都是經 `json()` 的 upstream 資料抓取；
  带 `sort=` 的是貼文頁；`about.json`／`by_id`／`duplicates` 是另一批端點。
- **分層判斷**：若同一份 body 是 HTML（`<body` 起頭）→ 被封鎖或被人機驗證擋；
  若是 JSON 但缺欄位 → 是 schema 漂移，不是封鎖。

## 2. 步驟二：找上游 issue / PR，並檢查它的基底

```bash
# 用 web_search / web_fetch 找 issue 與 PR（標題、錯誤訊息字串、route 名都當關鍵字）
# 關鍵檢查：PR 是否從「現行 main tip」分出（決定 merge 乾淨度）
git -C /tmp/redlib-triage fetch --no-tags --depth 300 origin pull/<n>/head:pr<n>
git -C /tmp/redlib-triage merge-base --is-ancestor origin/main pr<n> \
  && echo "branched from current main" || echo "branched from OLDER main → merge 有風險"
git -C /tmp/redlib-triage diff --stat $(git -C /tmp/redlib-triage merge-base origin/main pr<n>)..pr<n>
```

判讀要點（都要記錄）：
- 改了哪些檔、增刪行數；是否碰 `Cargo.lock`／`client.rs`／`oauth.rs`（高風險面）。
- 是否附測試、測試需不需要網路（`client.rs` 舊測試都打 Reddit，新的純函式測試才有價值）。
- 作者是否自陳「沒跑 `cargo check`／`clippy`」——若是，**我們的真實編譯就是必要的驗證**，不是加分項。
- 作者自標的 *not fixed / out of scope* 清單（例：同一事件裡 `/r/popular/hot.json` 與 Anubis PoW
  是鄰居問題，這支 PR 不處理）→ 這些要另外進 TODO，別誤以為一併修好。
- 上游是否已把它並入 main（`git cherry main refs/pr/<n> | grep -c '^-'`）→ 若已並入，
  走 `design/upstream-pr-bake.md` §5 的移除程序，不要重複 bake。

## 3. 步驟三：假設驗證——優先走容器 A/B，不要靠裸 curl

**陷阱（本次親身踩到）：無有效 token 的裸 curl 探測會給假陰性。**
用 redlib 源碼裡的公開 OAuth client id 去 mint token，若 grant 用錯
（redlib 的 MobileSpoof 走的是自訂端點，GenericWeb 走 `installed_client` grant，
都不是直覺的 `client_credentials`），拿不到 token；此時**兩種 URL 都回同一個 403 區塊頁**，
看起來「修法無效」，但那只是我們自己沒帶上認證。結論：

- 想裸探測就必須完整複製 redlib 的 token 流程（`src/oauth.rs` 的 `AUTH_ENDPOINT`、
  grant 字串、 spoof headers 全套）。成本高、易錯。
- **因此預設做法改成：直接 build 兩份映像做端到端 A/B。** 這同時驗證「修好」與
  「wreq/hyper 不會把編碼 normalise 掉」這類鏈路問題，比 curl 更接近真相。

```bash
# 一次準備兩份：含候選 PR / 不含（其餘條件完全相同）
rm -rf /tmp/ab && mkdir -p /tmp/ab/.build
cp Dockerfile /tmp/ab/ && cp .build/apply_redlib_prs.sh /tmp/ab/.build/
cp redlib-prs.txt /tmp/ab/redlib-prs.txt            # 含候選 PR 的版本
grep -v '^<n> ' /tmp/ab/redlib-prs.txt > /tmp/ab/prs-control.txt   # 對照組

docker build -t redlib-ab-fix     /tmp/ab                      # 用含 PR 的清單
# 再跑一次（把 prs-control.txt 當 redlib-prs.txt）→ redlib-ab-ctl

docker run -d --name ab-fix -p 8098:8080 redlib-ab-fix
docker run -d --name ab-ctl -p 8099:8080 redlib-ab-ctl
sleep 6
# 同一 URL 打兩邊，只比對「症狀是否消失」
for p in <報錯的 route>; do
  for port in 8099 8098; do
    code=$(curl -s -o /tmp/ab-$port.out -w '%{http_code}' "http://127.0.0.1:$port$p")
    printf 'port %s -> %s  symptom:%s\n' "$port" "$code" \
      "$(grep -c 'Failed to parse\|Reddit blocked' /tmp/ab-$port.out)"
  done
done
```

**判定成立的條件**：對照組必須**精確重現使用者回報的訊息**（不只是同狀態碼），
含 PR 組則消失。兩者缺一都代表我們測的不是同一個故障。
（本次：對照組 404 + 一模一樣的 parse error；含 PR 組 200、留言正常渲染。）

另外：`docker logs ab-fix` 要看得到 redlib 自己的 error log 行，用來分級
（真 404 應該是 `Reddit error 404 … Not Found`，而不是 parse error）。

## 4. 步驟四：回歸面（固定清單，跑兩邊對照）

| 面 | route | 預期 |
|----|-------|------|
| 列表 | `/r/rust`、`/r/popular`、`/r/all` | 200、無 parse error |
| 貼文頁（修正目標） | `/r/<sub>/comments/<id>/<slug>/` | 200、留言渲染 |
| 貼文頁變體 | `?sort=top`、`/comments/<id>/1`、`/comments/<id>/` | 200 |
| 重複貼文 | `/r/<sub>/duplicates/<id>` | 200（`/duplicates/` 通常不在被封集合） |
| 使用者 | `/u/<user>` | 302/200，非 parse error |
| 搜尋 | `/search?q=` | 200 |
| about | `/r/rust/about.json` | 正常 JSON 或 200 |
| 負controls | 不存在的 sub / 不存在的 post | **正確的 Reddit 404/400 錯誤頁**，不是 parse error |

負 control 特別重要：PR 若改了錯誤分級邏輯，這裡才是證據（把 block 誤報成 parse error
正是原 issue 難診斷的原因）。

> **grep 陷阱（2026-10-21 實測）**：redlib 的錯誤頁**範本本身**就帶有一段提到
> `Failed to parse page JSON data` 的協助手語，所以「在頁面 HTML 裡 grep 這個字串」會**假陽性**
> （不存在的 post 回真 404 時也會被計入）。真正的判別點是錯誤頁的標題/內文前綴
> （`Error: Reddit error 404 … Not Found`）與 container log 的 `Error page rendered: Reddit error <code> …`
> 行；要判 block 就只抓 `Reddit blocked this request (403` —— 這個串只來自 upstream 呼叫點的錯誤分級，
> 不會出現在範本裡。

### 4.1 逐功能（per-feature）核對的要領（2026-10-21 從雙架構線上實例學到）

1. **素材要從站內自己渲染的 HTML 裡挖，不要猜格式**。
   影片 proxy 的真實 URL 形狀（含大寫 `CMAF`/`DASH` prefix 與副檔名）、0 則留言的 post id
   （`title="0 comments"` 的 anchor）、分享連結要的作者名，全部從列表/貼文頁 HTML 解析出來再用。
   本次兩個猜錯的地方：影片路徑的 prefix 大寫與否；以及把 `?sort=` 當成排序入口（**它向來是 no-op**，
   真入口是路徑式 `/r/<sub>/new`、`/top?t=day`、`/controversial?t=week`）。
   猜錯入口會讓一個好端點看起來像回歸。
2. **探路由是否註冊：用「符合條件但不存在」的 id**。
   分享連結那個案例的決定性一招：`/u/<name>/s/<7字元真 id>` → `Nothing here`（路由沒接）
   對比 `/u/<name>/s/<8字元假 id>` → `Post ID is invalid…`（路由有接、但 guard 把真 id 拒掉）。
   三種結局（路由不存在 / 被 guard 擋 / 真的找不到）從錯誤訊息就能分辨，不需要讀源碼。
3. **對照映像只抽掉被懷疑的那一支 PR**，不是抽掉全部 bake（本次只抽 #521）：
   build 較快、結論是單因子，而且能直接證明該 PR 的價值（抽掉後 env 預設失效）。
4. **用 byte 數分類「上游行為 vs 我們的行為」**：同一 URL 在線上實例與本地同映像
   回傳 **byte 數完全一致**（不存在的 sub：6958=6958；stub 列表：9098≊9100），
   就不是部署/架構/設定問題，而是上游對 degenerate Reddit 資料的渲染方式。別在 bake 裡找原因。

## 5. 步驟五：tier 判定與落地

1. 依 `design/upstream-pr-bake.md` §2/§3/§4 決定 Tier（已 bake／可選待決策／不採用＋理由）。
2. 要 bake 就在 `redlib-prs.txt` 加一行 `<pr> <head-sha-前7碼> # 一行說明`，
   放在 merge 順序正確的位置（新修的 route/行為若與其他 PR 同檔，注意順序）。
   head SHA 只用於**漂移警示**（`apply_redlib_prs.sh` 用前綴比對，短 SHA 可）。
3. 更新 `upstream-pr-bake.md`：Tier 表一行（PR、head、內容、對我們的影響）、
   §7 驗證 checklist 加對應的線上項目、必要時 §8 加風險（**是否只是 workaround**、
   上游政策一變就會再壞 → 寫出可偵測的 observable 字串）。
4. `TODO.md` 放條目（P0＝線上壞掉中；P2＝需取捨）。**不要**在 TODO 寫 route/env/代碼標識符，
   那些留在本檔與 bake 檔。
5. 上線後用 registry 的 `<git-sha>` tag 記錄當時的 baked 組合（open PR 會 force-push，
   唯有 tag 能重現）。

## 6. 判定「根治 vs 繞行」的記帳要求

- 上游若用「迴避 Reddit 行為」的方式修（路徑編碼、UA spoof、header 排列），一律標為
  **繞行**，必須同時寫：觸發再壞的條件 + 再壞時使用者會看到的訊息字串 + 該訊息對應的源碼位置。
- 只有當 PR 改變 redlib 自身邏輯（panics、模板、設定讀取順序）才算根治。
- 對繞行項，保留一條可 grep 的 observable（container log 或錯誤頁字串），
  下次使用者回報時先 grep 它，能直接判定「是舊繞行失效」還是「新故障」。

## 7. 本次事件的具體資料（範例填法）

- 症狀：貼文頁 `Failed to parse page JSON data: expected value at line 1 column 1`，
  列表正常 → 呼叫點 = `client.rs` `json()`。
- 上游：issue #591、PR #592（2 commits：路徑編碼 + 錯誤分級）。基底 = 現行 main tip，
  只動 `src/client.rs`，附 5 個純函式測試，作者自陳未跑 `cargo check`/`clippy`。
- merge 實測：與 Tier 1 五支（#549/#542/#521/#560/#539）累積 `--no-ff` **全 clean**
  （#549 同碰 `client.rs` 但不同區塊）。
- A/B：對照組精確重現 parse error（404）；含 #592 組 200、標題與留言正常；
  §4 回歸清單全過，負 control 為正確 404/400 頁。
- 最終驗證是對**已發佈的映像**做的，不是對本地 test 映像：兩個 CI（本地 runner 多架構 + GitHub
  Actions amd64）都綠、log 都是 6 行 `Merging PR #<n>` 且無 `head moved` 警告；拉
  `codeberg.org/lawlietr/redlib:<git-sha>`（amd64+arm64 manifest list 都在）重跑 §4 清單全過。
  ghcr 那邊只能確認 build/push 成功（拉取需要 `read:packages` scope 的 token，現有 token 只有
  `repo`/`workflow`，所以拉 image 會被 `denied` —— 這不是映像的問題）。
- 定性：**繞行**（Reddit 若 normalise 該編碼就會再壞；屆時訊息為
  `Reddit blocked this request (403 Forbidden)`，對應 `client.rs` 的 `non_json_response_error()`）。
- 不在這支 PR 範圍、需另立條目：`/r/popular/hot.json` 的 parse error（上游 #589）、
  Anubis PoW 擋程式化存取（上游 #567）。
