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
> | 本 repo（Docker 設定、CI、文件） | **https://codeberg.org/Lawlietr/redlib_docker** |
> | 預編譯 container 映像 | `codeberg.org/lawlietr/redlib`（多平台 `linux/amd64` + `linux/arm64`；tag `latest` 與可 pin 的 `<git-sha>`） |
> | GitHub 鏡像（只是 GitHub Actions 的編譯入口） | https://github.com/Lawlietr/redlib_docker → 映像 `ghcr.io/lawlietr/redlib:latest`（**僅 amd64**、**只有 `latest`**；repo 與 package 公開，**匿名可拉**） |
>
> 兩者名稱不同：repo 是 `Lawlietr/redlib_docker`，registry 映像路徑是**小寫** `lawlietr/redlib`（Codeberg registry 要求小寫）。

- 建置時 clone upstream `main`（https://github.com/redlib-org/redlib），再把 **仍未合併進 upstream 的上游 PR** bake 進去：
  清單在 `redlib-prs.txt`（目前 #549/#542/#521/#560/#539/#592 → CMAF 影片與 `rich:video`、
  0 則留言 permalink panic、預設文章排序生效、使用者文章分享連結（**#560 的 id 條件有錯，現行 id 用不了**，見 `design/upstream-pr-bake.md` §8.9）、圖片 lazy-load、
  貼文頁路由編碼（**繞行 Reddit 封鎖，非根治**，見 `RELEASE_NOTES.md`）），
  由 `.build/apply_redlib_prs.sh` 套用。判斷依據、分級與重新評估程序：`design/upstream-pr-bake.md`。
  （#509 hyper-tls 已被 main 的 wreq 遷移 #544 取代，不 bake。）
- 產物為全靜態 binary，最終映像基於 `scratch`（約 13.5MB）。
- CI 自動建置並推送預編譯映像到 **`codeberg.org/lawlietr/redlib`**，
  支援 **`linux/amd64`** 與 **`linux/arm64`** 雙平台。

## 部署方式

### 1. Docker（拉取預編譯映像，推薦）

```bash
# 若映像設為私有，先登入：docker login codeberg.org
docker pull codeberg.org/lawlietr/redlib:latest

docker run -d \
  --name redlib \
  -p 8080:8080 \
  --restart unless-stopped \
  codeberg.org/lawlietr/redlib:latest
```

啟動後可透過 `http://localhost:8080` 存取。

### 2. Docker Compose

```yaml
# docker-compose.yml
services:
  redlib:
    image: codeberg.org/lawlietr/redlib:latest
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
> # A) 拉 CI 預編譯映像（推薦，等同上面的 image: 寫法）
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

## 映像標籤（Tags）

**兩個 registry 現在都是雙架構**（`linux/amd64` + `linux/arm64`），而且 **tag 命名一致**：

| Registry | `latest` | `<git-sha>` | 每架構 tag |
|---|---|---|---|
| `codeberg.org/lawlietr/redlib`（主，musl 全靜態） | ✅ manifest list | ✅ manifest list | `amd64` / `arm64` |
| `ghcr.io/lawlietr/redlib`（備援，glibc 靜態） | ✅ manifest list | ✅ 自 2026-10-21 | `amd64` / `arm64` |

| 標籤 | 說明 |
|------|------|
| `latest` | 最新建置（rolling tag，多平台 manifest list） |
| `<git-sha>` | 以 git commit SHA 標記的可重現版本（多平台） |
| `amd64` / `arm64` | 單架構映像，主要供 CI 內部 manifest merge 使用；一般使用者拉 `latest` 或 `<git-sha>` 就會自動選對架構 |

> ⚠ **兩個 registry 的 digest 不會相同**：`.forgejo/` 產的是 musl 靜態 binary，GitHub 端產的是
> glibc + `+crt-static` 靜態 binary（都是 `scratch`、行為一致，但不是同一個檔案）。跨 registry 時比 tag，
> 不要比 digest。ghcr 端自 2026-10-21 起公開，**匿名可拉**（不需 token）。

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

完整 changelog 在 **`RELEASE_NOTES.md`**（英文）。最近一輪（2026-10-21）要點：

- 貼文頁已恢復：bake 上游 #592，把 `/r/<sub>` 與 `comments` 之間那一個 slash 編碼成 `%2f`，
  避開 Reddit 對匿名 client 的**路徑規則**封鎖；同時把區塊錯誤改成明確的 403 訊息。
- ⚠ **這是暫緩之計，不是根治**：Reddit 的政策是把這類資料推向登入後才開放。
  一旦 Reddit 開始 normalise `%2f`，貼文頁會**再度全數失效**；屆時看到的是
  `Reddit blocked this request (403 Forbidden): …`，不是 parse error。
  重啟容器（換 token）無效 —— 封鎖是按路徑，不是按 token。
- 同一事件的上游 #589（首頁 feed parse error）與 #567（Anubis PoW）**不在這輪修正範圍**。

## CI/CD

- 觸發：`Dockerfile`、`Dockerfile.pack`、`redlib-prs.txt`、`.build/**`、`.forgejo/scripts/build_and_push.sh` 變動，或手動 "Run workflow"。
- 執行環境：本機自架 Forgejo Runner（`redlib` label），musl 原生交叉編譯 amd64/arm64（無 QEMU）+ BuildKit/cargo cache mount（增量建置）。
- 推送目標：`codeberg.org/lawlietr/redlib`，
  每輪建置產生 `latest`（rolling）與 `<git-sha>`（可重現 pin）兩個多平台 manifest list，
  同時包含 `linux/amd64` 與 `linux/arm64`。
- GitHub Actions（`.github/workflows/build.yml`）：**矩陣兩個 job + 一個 manifest job**。
  amd64 在 `ubuntu-latest`、arm64 在 `ubuntu-24.04-arm`（public repo 免費的原生 arm64 hosted runner），
  都用**同一份** `Dockerfile` 與同一份 PR bake 原生編譯，各自推 `:amd64`/`:arm64`，
  再由 `.github/scripts/merge_manifest.sh` 以 `docker buildx imagetools create` 合併成
  `ghcr.io/lawlietr/redlib:{latest,<git-sha>}`（多平台 manifest list）。細節：`design/github-actions-workflow.md`。
- 細節與故障排除：`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`、`design/multi-arch-build.md`。

## 故障排除

- **建置失敗**：確保網路連線正常（build 會 clone upstream 與拉取 Rust 套件）；
  boring-sys2（BoringSSL）需要 cmake + C 編譯器 + libclang，builder 映像已內建。
- **容器無法啟動**：檢查 8080 端口是否被佔用；用 `docker logs redlib` 查日誌。
- **更新後還是舊版**：`latest` 是 rolling tag，已拉過的主機要重新 `docker pull` 並 recreate；
  用本 repo 的 compose 時記得 `--no-build`（見上方 A) 模式），否則 `up -d` 會用本地 build 的產物。
- **build 時 merge 衝突 / `warning: PR #<n> head moved`**：上游或 PR 漂移，
  照 `design/upstream-pr-bake.md` §5 重新評估 `redlib-prs.txt`。

## 專案資訊

- 原始碼：https://github.com/redlib-org/redlib
- Docker 個人實作，非官方專案
- License：本 repo 自有檔案（Dockerfile、腳本、設定）為 MIT；upstream redlib 保留 AGPL-3.0
