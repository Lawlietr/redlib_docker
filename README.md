| 🇬🇧 | [English](README_EN.md) |
| 🇹🇼 | 繁體中文 |

# Redlib Docker

輕量級 Reddit 替代方案，透過 Docker 部署。

- 建置時 clone upstream `main`（https://github.com/redlib-org/redlib），再把 **仍未合併進 upstream 的上游 PR** bake 進去：
  清單在 `redlib-prs.txt`（目前 #549/#542/#521/#560/#539 → CMAF 影片與 `rich:video`、
  0 則留言 permalink panic、預設文章排序生效、使用者文章分享連結、圖片 lazy-load），
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

## 映像標籤（Tags）

所有標籤皆為多平台 manifest list（`linux/amd64` + `linux/arm64`）：

| 標籤 | 說明 |
|------|------|
| `latest` | 最新建置（rolling tag） |
| `<git-sha>` | 以 git commit SHA 標記的可重現版本 |

> **注意**：`amd64` 與 `arm64` 標籤也存在於 registry 中，但僅供 CI 內部
> manifest merge 使用，不建議使用者直接拉取。
>
> 另有 GitHub Actions 產的鏡像備援 `ghcr.io/lawlietr/redlib:latest`（**僅 amd64**；
> repo 為 private → package 也是 private，拉取需 `read:packages` token）。

## CI/CD

- 觸發：`Dockerfile`、`Dockerfile.pack`、`redlib-prs.txt`、`.build/**`、`.forgejo/scripts/build_and_push.sh` 變動，或手動 "Run workflow"。
- 執行環境：本機自架 Forgejo Runner（`redlib` label），musl 原生交叉編譯 amd64/arm64（無 QEMU）+ BuildKit/cargo cache mount（增量建置）。
- 推送目標：`codeberg.org/lawlietr/redlib`，
  每輪建置產生 `latest`（rolling）與 `<git-sha>`（可重現 pin）兩個多平台 manifest list，
  同時包含 `linux/amd64` 與 `linux/arm64`。
- GitHub Actions（`.github/workflows/build.yml`）：用**同一份** `Dockerfile` 與同一份 PR bake，在 `ubuntu-latest` 原生編 amd64 → `ghcr.io/lawlietr/redlib:latest`。細節：`design/github-actions-workflow.md`。
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
