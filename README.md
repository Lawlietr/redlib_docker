| 🇬🇧 | [English](README_EN.md) |
| 🇹🇼 | 繁體中文 |

# Redlib Docker

輕量級 Reddit 替代方案，透過 Docker 部署。

> ## 這個 repo 在做什麼：**合併與打包**，不是 fork
>
> 這裡**沒有 redlib 的原始碼**，也不是 upstream 的分支或 fork。build 時才 clone upstream `main`，
> 再把 **upstream 自己提交、尚未被合併的 PR** merge 進去，然後打包成 Docker 映像。
> 所有功能改動的來源都是 upstream 與其 PR，本 repo 只負責**合併（bake）與打包**，外加 CI、Docker 設定與文件。
> 因此 repo 裡不會出現 redlib 的 `src/`；要讀原始碼或提 bug 請到 upstream：https://github.com/redlib-org/redlib
>
> **存放位置**
>
> | 項目 | 位置 |
> |------|------|
> | 本 repo（Docker 設定、CI、文件） | **https://codeberg.org/Lawlietr/redlib_docker**（另有 GitHub 鏡像 https://github.com/Lawlietr/redlib_docker） |
> | **預編譯 container 映像（主，2026-10-21 起）** | **`ghcr.io/lawlietr/redlib`** — 由 **GitHub Actions** 自動建置，雙架構 `linux/amd64` + `linux/arm64`；tag `latest` 與可 pin 的 `<git-sha>`；公開，**匿名可拉** |
> | 同一批映像的鏡像 | `codeberg.org/lawlietr/redlib` — **由 GitHub Actions 以 registry 側 copy 鏡像過去**（不重新編譯），tag 與 **digest 兩邊相同**；那條手動備援路（`.forgejo/workflows/build.yml`）會把這些 tag 暫時換成它自己的產物，直到下一次 CI 把鏡像蓋回來 |
>
> 名稱差異要注意：repo 是 `Lawlietr/redlib_docker`（Codeberg 上大小寫自如顯示），registry 映像路徑是**小寫** `lawlietr/redlib`（registry 要求小寫，兩個登錄區都如此）。

- 建置時 clone upstream `main`（https://github.com/redlib-org/redlib），再把 **仍未合併進 upstream 的上游 PR** bake 進去：
  清單在 `redlib-prs.txt`（目前 #549/#542/#521/#560/#539/#599 → CMAF 影片與 `rich:video`、
  0 則留言 permalink panic、預設文章排序生效、使用者文章分享連結（**#560 的 id 條件有錯，現行 id 用不了**，見 `design/upstream-pr-bake.md` §8.9）、圖片 lazy-load、
  貼文頁留言改從 Reddit 前端的 HTML fragment 取得（**繞行 Reddit 對 comments API 的封鎖，非根治，且不完整**，見下方「上游狀態」與 `RELEASE_NOTES.md`）），
  由 `.build/apply_redlib_prs.sh` 套用。判斷依據、分級與重新評估程序：`design/upstream-pr-bake.md`。
  （#509 hyper-tls 已被 main 的 wreq 遷移 #544 取代，不 bake。）
- 產物為全靜態 binary，最終映像基於 `scratch`（約 13.5MB；含 #599 的 HTML parser 相依後約 14.8MB）。
- **未來鏡像一律由 GitHub Actions 編譯並推送**到主登錄區 **`ghcr.io/lawlietr/redlib`**（雙平台
  `linux/amd64` + `linux/arm64`），**隨後自動鏡像到 `codeberg.org/lawlietr/redlib`**（registry 側 copy、不重新編譯，
  tag 與 digest 兩邊相同）。本地 Forgejo runner 那條路**保留**但改為**只手動觸發**（GitHub 整天不可用時的緊急備援，不是一個產品線）；
  本機 `docker build` 也支援，適合改動測試與離線除錯。

## 部署方式

### 1. Docker（拉取預編譯映像，推薦）

```bash
# 主登錄區（ghcr 公開，匿名可拉，不需 docker login）
docker pull ghcr.io/lawlietr/redlib:latest

docker run -d \
  --name redlib \
  -p 8080:8080 \
  --restart unless-stopped \
  ghcr.io/lawlietr/redlib:latest

# 要固定版本就用 <git-sha> tag：
#   docker pull ghcr.io/lawlietr/redlib:d572b2e
# 同一批映像也會鏡像到 Codeberg 登錄區（tag 與 digest 相同）：
#   docker pull codeberg.org/lawlietr/redlib:latest
```

啟動後可透過 `http://localhost:8080` 存取。

### 2. Docker Compose

```yaml
# docker-compose.yml
services:
  redlib:
    image: ghcr.io/lawlietr/redlib:latest
    container_name: redlib
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      # Optional (see .env.example for full list):
      #   - REDLIB_DEFAULT_THEME=dark
      #   - REDLIB_DEFAULT_FRONT_PAGE=popular
      #   - REDLIB_DEFAULT_LAYOUT=compact
      #   - REDLIB_DEFAULT_POST_SORT=hot
      #   - REDLIB_DEFAULT_SHOW_NSFW=on
      #   - REDLIB_BANNER=Welcome to my Redlib instance
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256M
        reservations:
          cpus: "0.25"
          memory: 64M
```

```bash
docker compose up -d
```

> 本 repo 根目錄的 `docker-compose.yaml` 同時支援兩種來源（同一個 service，用 `REDLIB_IMAGE` 切換）：
>
> ```bash
> # A) 拉 CI 預編譯映像（主路徑：GitHub Actions 產的 ghcr）
> REDLIB_IMAGE=ghcr.io/lawlietr/redlib:latest docker compose up -d --pull always --no-build
>
> # A2) 備援登錄區（現在只在手動跑 `.forgejo/workflows/build.yml` 時才更新）
> REDLIB_IMAGE=codeberg.org/lawlietr/redlib:latest docker compose up -d --pull always --no-build
>
> # B) 本地從原始碼建置（以本 repo 為 context build 根目錄 `Dockerfile`，含 PR bake）
> docker compose up -d --build
> ```
>
> ⚠ 只要 service 裡有 `build:`，**不帶 `--no-build` 的 `docker compose up -d` 一律用本地 build 的產物**，
> 不會拉 registry 映像；`latest` 是 rolling tag，換新版一定要重新 pull + recreate。

### 3. 從原始碼建置（手動 build）

```bash
docker build -t redlib .
docker run -p 8080:8080 -d --name redlib redlib

# 指定 Redlib 分支（預設 main）
docker build --build-arg REDLIB_BRANCH=main -t redlib .
# 指定上游 git 來源
docker build --build-arg REDLIB_SRC=https://github.com/redlib-org/redlib.git -t redlib .
```

> **Bake 說明**：build 會自動把 `redlib-prs.txt` 列出的 PR merge 進 clone 好的原始碼
> （`.build/apply_redlib_prs.sh`，一般 `--no-ff` merge）。上游或 PR 漂移時：
> log 會出現 `warning: PR #<n> head moved`（僅警示），或 merge 衝突直接讓 build 失敗 ——
> 這是刻意的，避免靜默吃掉上游改動；處理程序見 `design/upstream-pr-bake.md` §5。
>
> **可重現性說明**：Dockerfile 在 build 時 clone 上游 `main` 的**當下狀態**，PR head 也可能被 force-push。
> 我們推送的 `latest` 是某個時間點的快照，你自己 build 會得到「同一套構建流程 + 當天的 redlib 版本」，
> 與我們的映像不保證 bit-for-bit 相同。需要固定版本時：拉 registry 的 **`<git-sha>` tag**，
> 或 `--build-arg REDLIB_BRANCH=<commit 或 tag>` pin 住。
>
> **上游狀態（v0.40.0，2026-10-22 核對；當時五支，2026-10-23 起六支，見下一段）**：當時 bake 的五支 PR **全部仍未被上游以 PR 形式合併**，
> 一律照 bake。其中 #592（thread 頁 403 的 workaround）在上游 `main` 已有一份**等效的直接 commit**
> （`0a3e9cd fix: encode anonymous comments request paths`，把 subreddit 與 `comments` 之間的斜線編成 `%2F`）。
> 本 repo 只做「合併與打包」而非 fork，判定標準是「該 PR 有沒有被上游合併」；#592 作為 PR 從未整合、
> 但上游已用同一招補上，保留它只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故**已將 #592 從 bake 清單退役**，
> 因此改由上游版本供應——它仍是 workaround 不是 root fix，re-break 風險與 observable（`client.rs` 的
> block / 解析錯誤）不變。
>
> **2026-10-27 更新：#592 已被上游正式關閉（未 merge），但我們不需要做任何事。** 維護者在 2026-10-21 直接
> close 該 PR（`mergeable=false`、0 review），它的兩支 commit **從未**以 patch-equivalent 進 `main`（`git cherry -v`
> 檢查兩支都還是 `+`），而我們的「改用上游等效 commit、把 #592 退役」判定到現在都正確。同一輪也把上游那個
> `%2F` 繞行**正式判死**：用同一份清單**拿掉 shreddit 那支 PR** 建的對照映像，在**兩台機器、四條貼文上都拿不到留言**
> （404 + parse error）→ 代表 **shreddit 那支 PR 是 load-bearing**，不能因為它是 workaround 就移除。
>
> **2026-10-23 追加 bake：#599（⚠ 未完全解決問題）**
>
> 上面那個 `%2F` 編碼繞行**已被 Reddit 識破**：正式實例重新出現
> `Failed to parse page JSON data: expected value at line 1 column 1 | /r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`，
> 而 upstream `main` 自 v0.40.0（HEAD `ba116c1`）之後沒有任何新 commit，也就是**上游當時完全沒修**。
> 於是 bake 上游 [#599](https://github.com/redlib-org/redlib/pull/599)：它不再碰 comments API，
> 文章改由 `/by_id/t3_<id>.json` 取，**留言改抓 Reddit 前端自己用的 `/svc/shreddit/comments/...` HTML fragment**，
> 用 `scraper` 解析回原本 JSON 的形狀，所以 `parse_comments` 與模板不用改。
>
> 本地 x86-64 build + 起容器實測通過（貼文頁 200、留言有正文、permalink + `?context=3` 正常、留言排序真的生效、
> 0 則留言不 panic、panic 0）。**但它只把「整頁壞掉」換成「能用但有損」，以下都是已知代價：**
>
> 1. **仍是 workaround，而且比 #592 更脆**：打的是 Reddit **未文件化的內部 fragment 端點**，Reddit 關掉就全壞；
>    該 PR 是 **AI 生成、0 review、上游 CI 從沒跑過**（head `26c02193`，0 個 check runs；2026-10-23 首次 bake 時是 `0db637cd`）。
> 2. **反限流很脆**：captcha 偵測靠比對字面 `<title>Reddit - Prove your humanity</title>`，再加上 429 與
>    `x-ratelimit-remaining < 20` 就輪替 cookie session。字串一改，challenge 頁會被當成正常留言內容解析。
> 3. **請求放大**：每個未 cache 的貼文頁要 **1–31 個** Reddit 請求（本機實測**冷 3.07s / 熱 0.019s**，listing 對照 0.74s），
>    而 cache 只有 30 秒；shreddit 的 cookie session 是 **process-global**，代表同一實例的所有訪客共用一份配額，
>    人一多就會互相吃光（上游 #597 / #446 已在抱怨 rate limit）。踩到時的訊息：
>    `Reddit is rate limiting comment requests. Try refreshing in a few seconds.`
> 4. **留言上限 200 則**：多出來的部分變成「More replies」殘根（本機實測大討論串剩 93–106 個未展開殘根）。
> 5. **留言少了 author flair 與 awards**（fragment 裡沒有這些欄位）；quarantined subreddit 的 shreddit 行為未測。
> 6. **subreddit 名稱不再被驗證**：文章改走 `by_id`，而它不看 subreddit → 錯的 sub 加上對的 post id 也會 200 並顯示別篇文章
>    （本機實測 `/r/__totally_wrong_sub__/comments/1xbt0if/x/` 回 200、內容是 r/masseffect 那篇）。上游 `main` 對這種 URL 是 404。
> 7. **不在範圍**：首頁 feed 的 parse error（上游 #589）與 Anubis PoW 擋程式化存取（#567）照舊；
>    而且整套仍依賴 `by_id/t3_<id>.json` 沒被封 —— 一旦被封，貼文頁再度全滅。
> 8. 體積與供給面：新增 25 個 crate（`scraper`/`html5ever`/`cssparser`/`phf`…），映像 13.5MB → 14.8MB。
>
> **再壞時要 grep 的 observable**（照 `design/error-triage-playbook.md`）：
> `Reddit returned <status> | /svc/shreddit/...`、`Reddit is rate limiting comment requests...`、
> `Refusing to fetch non-shreddit path`，或舊的那串 parse error（代表 `by_id` 也被封）。
> 分級與判定依據：`design/upstream-pr-bake.md` §2、§8.12。
>
> **2026-10-27 評估：上游 #603（留言改走 Android persisted GraphQL）——判定不 bake。** 它把 #599 那條路**取代**而非補上
> （兩者改同一行留言 fetch，同時 bake 一定衝突），所以這是**二選一**而不是加一支。實測（三支配方同一條 bake 鏈、兩台機器）：
> 在出口不被擋的機器上 #603 **能動而且快 2.7–4×**（同貼文 1.02s vs 2.42s；1.13s vs 3.06s）並用 `cursor` 真的突破每頁
> 200 則上限（下一頁 200 / 58,810 B / 0.36s），但它**在被 Reddit 擋出口 IP 的那台上照樣 0 則留言**，而且把依賴從
> 「未文件化的 HTML fragment」換成「未文件化的 GraphQL persisted query hash」（同級脆弱、少一條退路）、每頁留言數
> 240 → 200。重啟評估的三個觸發條件與全部數據見 `design/upstream-pr-bake.md` §8.14。

> **2026-10-27 pin 更新（`0db637cd` → `26c02193`）**：#599 在我們首次 bake 之後又多三支 commit ——
> `rdt` bot-check 的 302 不再報錯、留言裡的 GIF/影片從空的可點方塊變成原生 `<video>`、以及**最要緊的一支**：
> Reddit edge 開始把**沒帶 `Origin`/`Referer` 的「more comments」POST 回 403**，而且 shreddit 對**行動端**模擬
> 每個 fragment 只給 10 則留言（桌面 25 則）→ 新 pin 補上瀏覽器 headers 並讓 shreddit 用**自己的桌面 client**。
> 也就是说：**現行已發佈的映像（pin `0db637cd`）正處於「留言展開被抑 / 每頁只有十則」的退化狀態**。
> 新 head 只碰 `src/client.rs` 與 `src/shreddit.rs`，**`Cargo.toml`/`Cargo.lock` 零變化** → 相依與映像體積不變。
> 仍**未修**：留言圖片 overflow 容器（上游 2026-10-27 回報，之後零 commit）、200 則上限、其餘 §8.12 缺口。

> ⚠ **`redlib-prs.txt` 裡那欄 SHA 只是「漂移警示」，不是版本鎖定**：建置一律拿 PR 的**當前** head
> （`refs/pull/<n>/head` 永遠只有最新 head）。要重現過去某一組 bake 組合，用
> `docker build --build-arg BAKE_ARGS=--at-listed-sha`；要拉可重現的產物，**pin `<git-sha>` tag 或 digest**。
> 完整說明：`RELEASE_NOTES.md` 2026-10-27 條目、`design/upstream-pr-bake.md` §6。

> ⚠ **換 pin 不會修好「出口是機房 IP」的實例**：同一個 digest 在 OCI（Oracle 出口）上貼文頁照樣 404，
> 頁面寫 `Reddit returned 403 Forbidden | /svc/shreddit/comments/r/<sub>/t3_<id>`，而住宅出口的機器完全正常
> → 那是**出口 IP 信譽**，不是 code。掛 Cloudflare CDN 也不會改變（CDN 代理的是**進向**；
> redlib 打 Reddit 的請求由該機器自己直接發出，不經過 CF）。判別 SOP：`design/error-triage-playbook.md` §4.2、
> `design/upstream-pr-bake.md` §8.13。
> **反向代理、ZeroTier、VPN 都只在入口側**，不會改變 Reddit 看到的出口 IP：我們三台雲主機（o1/o2/o3，全 `AS31898` Oracle Tokyo）資源都夠跑 redlib（idle RSS 約 43MB），但貼文頁全是 `Reddit returned 403 Forbidden | /svc/shreddit/...`；能動的實例是跑在區網 Ubox-02（123）那台，前門在 o3 也只是把請求轉進 ZeroTier。拓撲與實測：`design/reverse-proxy-front.md`。

## 映像標籤（Tags）

**兩個 registry 現在都是雙架構**（`linux/amd64` + `linux/arm64`），而且 **tag 命名一致**：

| Registry | 角色 | `latest` | `<git-sha>` | 每架構 tag |
|---|---|---|---|---|
| `ghcr.io/lawlietr/redlib` | **主**（GitHub Actions，push 自動跑；glibc 靜態產物） | ✅ manifest list | ✅ manifest list | `amd64` / `arm64` |
| `codeberg.org/lawlietr/redlib` | **鏡像**（CI 用 `imagetools` 做 registry 側 copy，內容與 digest 同 ghcr） | ✅ manifest list | ✅ | `amd64` / `arm64` |

| 標籤 | 說明 |
|------|------|
| `latest` | 最新建置（rolling tag，多平台 manifest list） |
| `<git-sha>` | 以 git commit SHA 標記的可重現版本（多平台） |
| `amd64` / `arm64` | 單架構映像，主要供 CI 內部 manifest merge 使用；一般使用者拉 `latest` 或 `<git-sha>` 就會自動選對架構 |

> ⚠ 現在 `codeberg.org/lawlietr/redlib` 的 tag 是 GitHub Actions **鏡像**過去的，所以**同一 tag 的 digest 兩邊相同**，
> 用 digest pin 可以在兩個登錄區間通用。**例外**：手動跑 `.forgejo/workflows/build.yml` 會把這些 tag 指向
> 它自己的產物（digest 就會不同），直到下一次 CI 建置把鏡像蓋回來。兩個登錄區都公開，**匿名可拉**。

## Fork 之後能輕易產自己的鏡像嗎？

能——這正是本 repo 只做「合併與打包」（不含 redlib 源碼）的好處：fork 不需要改任何檔案就能得到自己的鏡像。

| 項目 | fork 後的行為 |
|------|----------------|
| 本機 build | `docker build -t redlib .` 開箱可用，**不需任何 secret**（`Dockerfile` 只抓公開的 upstream 與 `pull/<n>/head`）；只產**本機架構** |
| GitHub Actions | guard 是 `github.server_url == 'https://github.com'`，在自己的 GitHub fork 上為真 → push 到自己 `main` 就自動跑（amd64 + arm64 兩個 job + manifest job） |
| 推送目標 | **`ghcr.io/<自己的 owner（自動小寫）>/redlib`** — namespace 由 `$GITHUB_REPOSITORY_OWNER` 推導，**不用改腳本**；也不會碰到我們的 namespace |
| 需要設的 secret | **無**。只用 `${{ secrets.GITHUB_TOKEN }}`（Actions 自動提供），`permissions: contents/packages: write` 已在 workflow 內声明（首次推送自動建立 package） |
| 不會跑的路 | `.forgejo/**`（要自架 runner + `CODEBERG_PAT`；該 workflow 在 GitHub 上也不會被解譯） |
| 換 PR 組合 | 只改 `redlib-prs.txt`（每行 `<PR 編號> <reviewed head SHA> # 註記`）。上游漂移導致 merge 衝突時 build 會**響亮失敗**，不會靜默吃掉改動（`design/upstream-pr-bake.md` §5） |

**fork 要注意的四件事**：

1. fork 上 **Actions 預設關閉**，要在 Actions 頁點一次啟用，否則 push 不會跑。
2. 觸發條件：`Dockerfile`、`redlib-prs.txt`、`.build/**`、`.github/**` 變更（或手動 dispatch）；只改文件不會重建。
3. **從 fork 開 PR 不會推鏡像**（workflow 不監聽 `pull_request`），只有 push 到自己的 `main` 才會。
4. ghcr package 的**能見度繼承 repo**：fork 是 private → `ghcr.io/<fork owner>/redlib` 也是 private，
   匿名拉取會被 `denied`（看起來像「鏡像不存在」，實際是能見度問題；symptom 對照表見 `design/github-actions-workflow.md` §3）。

## 環境變數

參考 `.env.example` 完整清單。常見變數：

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `PORT` | 8080 | 伺服器端口 |
| `REDLIB_DEFAULT_THEME` | system | 預設主題（system/light/dark/black/dracula/nord/laserwave/violet/gold/rosebox/gruvboxdark/gruvboxlight） |
| `REDLIB_DEFAULT_FRONT_PAGE` | default | 預設首頁（default/popular/all） |
| `REDLIB_DEFAULT_LAYOUT` | card | 預設版面（card/clean/compact） |
| `REDLIB_DEFAULT_POST_SORT` | hot | 預設文章排序（hot/new/top/rising/controversial） |
| `REDLIB_DEFAULT_COMMENT_SORT` | confidence | 預設留言排序（confidence/top/new/controversial/old） |
| `REDLIB_DEFAULT_SHOW_NSFW` | off | 預設顯示 NSFW 內容 |
| `REDLIB_DEFAULT_FILTERS` | （空） | 預設過濾 subreddit（格式：sub1+sub2+sub3） |
| `REDLIB_DEFAULT_SUBSCRIPTIONS` | （空） | 預設訂閱 subreddit（格式：sub1+sub2+sub3） |
| `REDLIB_BANNER` | （空） | 執行個體橫幅訊息 |
| `REDLIB_SFW_ONLY` | off | SFW-only 模式 |
| `REDLIB_ROBOTS_DISABLE_INDEXING` | off | 關閉搜尋引擎索引 |

完整清單：https://github.com/redlib-org/redlib/blob/main/.env.example

## 更新說明（Release notes）→ `RELEASE_NOTES.md`

完整 changelog 在 **`RELEASE_NOTES.md`**（英文）。最近兩輪要點：

- **2026-10-23 — bake #599，貼文頁重新有留言**：留言不再走 comments API，改抓 Reddit 前端的
  `/svc/shreddit/comments/...` HTML fragment 重建。⚠ **不完整、非根治**：留言上限 200 則、少了 author flair
  與 awards、每個未 cache 的貼文頁吃 1–31 個請求（冷開 3s）、shreddit cookie session 全實例共用、
  subreddit 名稱不再被驗證，而且打的是未文件化的內部端點 —— 逐條說明見上方「上游狀態」與 `RELEASE_NOTES.md`。
- **2026-10-22 — #592 退役**：上游 v0.40.0 以直接 commit `0a3e9cd` 供應同等的 `%2F` 編碼繞行，保留 #592 只會衝突。
- ⚠ **2026-10-21 那輪的 `%2f` 編碼繞行已失效**：Reddit 已把編碼後的路徑也一起擋掉（實測：正式實例的貼文頁又回到 parse error）。
  重啟容器（換 token）從來就不是解法 —— 封鎖是按路徑，不是按 token。
- 同一事件的上游 #589（首頁 feed parse error）與 #567（Anubis PoW）**不在修正範圍**。

## CI/CD

**主路徑（2026-10-21 起）：GitHub Actions**。

- GitHub Actions（`.github/workflows/build.yml`）：**push 到 `main` 且動到 `Dockerfile`、`redlib-prs.txt`、`.build/**`、`.github/**` 就自動跑**（或手動 "Run workflow"）；
  **矩陣兩個 job + 一個 manifest job**：amd64 在 `ubuntu-latest`、arm64 在 `ubuntu-24.04-arm`（public repo 免費的原生 arm64 hosted runner），
  都用**同一份** `Dockerfile` 與同一份 PR bake 原生編譯，各自推 `:amd64`/`:arm64`，
  再由 `.github/scripts/merge_manifest.sh` 以 `docker buildx imagetools create` 合併成
  `ghcr.io/lawlietr/redlib:{latest,<git-sha>}`（多平台 manifest list）。並發以 `concurrency.group` 串行，
  避免 manifest merge 混到不同 commit 的兩個架構。細節：`design/github-actions-workflow.md`。
- **保留但不自動跑：本地 Forgejo runner**（`.forgejo/workflows/build.yml`，12 機 `redlib` label）。
  2026-10-21 起 `push` 觸發已移除，**只剩 `workflow_dispatch`**（可選填 reason）。用途：
  只作為 GitHub Actions 不可用時的緊急備援（或你刻意要在自己網路內重產一份時）。它產的是 musl 交叉編譯的
  成品 —— 這只是**那條路的實作細節**（x86 機器上要交叉編 arm64，musl 最省事），**不是對外承諾的二進位格式**；
  主產物一律是 ghcr 的 glibc 靜態版，Codeberg 由鏡像取得。
  runner 基礎設施與磁碟紀律（30GB、`disk_guard.sh` + prune）完整保留，見 `design/forgejo-runner-workflow.md`、
  `design/forgejo-runner-deployment.md`、`design/multi-arch-build.md`。
- **`codeberg.org/lawlietr/redlib` 由同一條 CI 鏡像維護**：manifest 合併完之後，`mirror-codeberg` job 用
  `docker buildx imagetools create` 把 `:latest`/`:<git-sha>`/`:amd64`/`:arm64` **原樣複製**過去（不重新編譯，
  約 13MB），因此 tag 與 digest 兩邊一致。該 job 需要 GitHub 端的 `CODEBERG_PAT` secret（`write:packages`），
  **沒設就會明確失敗**（不會靜默略過）。細節：`design/github-actions-workflow.md` §9。
- **發佈前有 `smoke` job**（`needs: manifest`）：把剛推出的 `:amd64` 鏡像在乾淨 runner 上跑起來，打 `/`、
  `/r/gaming`、`/r/AskReddit/top`，先確認鏡像內的 binary 全靜態、架構正確，再起容器打這三個 route、檢查狀態碼與 body 大小、掃 log 找解析器錯誤 ——
  專抓「靜態 binary 在 `scratch` 內無法做 DNS」與「bake 的 PR 在執行期壞掉」這兩類只有上線才會發現的問題；`mirror-codeberg`
  `needs: smoke`，沒通過就不會鏡像。細節：`design/github-actions-workflow.md` §10。
- ⚠ 如果你**手動**跑 Forgejo 那條備援建置，它會把 codeberg 的 tag 換成它自己的產物（digest 與 ghcr 不同），
  直到下一次 GitHub 建置把鏡像蓋回來。
- 驗證每一步的做法：`design/error-triage-playbook.md`；逐功能回歸清單：`design/upstream-pr-bake.md` §7。

## 本地編譯與測試（改動前後都建議跑）

CI 不是唯一入口，本地 build + 起容器驗證是**明確支援**的做法（改動前後都建議跑；CI 的 `smoke` job 做的是
同一類檢查，只是對象是已發佈的鏡像）：

```bash
# 1) build（只產本機架構；含 redlib-prs.txt 的 PR bake）
docker build -t redlib-local .
#    換 upstream 分支/commit：--build-arg REDLIB_BRANCH=<branch|tag|sha>

# 2) 起起來（預設 8080，避開佔用就換埠）
docker run -d --name redlib-local -p 8090:8080 redlib-local

# 3) 四條快速 smoke（完整清單見 design/upstream-pr-bake.md §7）
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8090/r/SteamdeckGames/comments/1xautuo/horizon_forbidden_west_should_not_be_steam_deck/'
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8090/r/__definitely_no_such_sub__/comments/1xautuo/x/'   # 負 control：要 404/400，不是 200
docker logs redlib-local 2>&1 | grep -ci panic   # 要 0
```

要點：
- **只產本機架構**。在 x86_64 上不會幫你產 arm64；本機也沒有 qemu binfmt，`--platform linux/arm64`
  會 `exec format error`（arm64 的執行驗證要真 arm64 硬體，見 `TODO.md`）。
- **別用裸 curl 探 Reddit API** 來判斷成敗——會給假陰性；要比就比「同一份代碼含/不含候選 PR」的**雙映像端到端 A/B**，
  手法見 `design/error-triage-playbook.md`。
- 本地 build 的產物 **不推 registry**，也不會動到兩個登錄區；要發佈只能走 CI（或手動跑 `.forgejo/`）。

## 故障排除

- **建置失敗**：確保網路連線正常（build 會 clone upstream 與拉取 Rust 套件）；
  boring-sys2（BoringSSL）需要 cmake + C 編譯器 + libclang，builder 映像已內建。
- **容器無法啟動**：檢查 8080 端口是否被佔用；用 `docker logs redlib` 查日誌。
- **更新後還是舊版**：`latest` 是 rolling tag，已拉過的主機要重新 `docker pull` 並 recreate；
  用本 repo 的 compose 時記得 `--no-build`（見上方 A) 模式），否則 `up -d` 會用本地 build 的產物。
- **build 時 merge 衝突 / `warning: PR #<n> head moved`**：上游或 PR 漂移，
  照 `design/upstream-pr-bake.md` §5 重新評估 `redlib-prs.txt`。注意預設行為**只是警告**，建置照樣用 PR 的
  當前 head（那欄 SHA 不是版本鎖）；要真的重現歷史組合：`docker build --build-arg BAKE_ARGS=--at-listed-sha`。
- **貼文頁又壞 / 留言變空 / 出現 rate-limit 訊息**：先分清楚是哪一層壞 ——
  `Reddit returned <status> | /svc/shreddit/...`（#599 的 fragment 端點被擋）、
  `Reddit is rate limiting comment requests. Try refreshing in a few seconds.`（cookie session 配額被吃光）、
  舊的 `Failed to parse page JSON data...`（連 `by_id` 也被封）。溯源 SOP：`design/error-triage-playbook.md`。
- **同一支映像，A 機能用、B 機貼文頁全壞**：先比 `docker images --digests` 確認是**同一個 manifest digest**，
  再從兩台 host 用**帶瀏覽器 headers** 的 curl 打 `/svc/shreddit/comments/r/<sub>/t3_<id>`：
  住宅 IP 200、機房 IP（Oracle/Hetzner/Vultr/AWS…）403 → **出口 IP 被 Reddit 封**，重產映像/換 env/重啟容器都無效。
  掛 Cloudflare CDN 也不會救（CDN 只在進向）。做法：`design/error-triage-playbook.md` §4.2。

## 專案資訊

- 原始碼：https://github.com/redlib-org/redlib
- Docker 個人實作，非官方專案
- License：本 repo 自有檔案（Dockerfile、腳本、設定）為 MIT；upstream redlib 保留 AGPL-3.0
