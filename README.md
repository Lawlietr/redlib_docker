# Redlib Docker

輕量級 Reddit 替代方案，透過 Docker 部署。

- 建置時直接 clone upstream `main`（https://github.com/redlib-org/redlib），
  曾手動 bake 的 PR（#506/#509/#521/#560/#539/#549）現已全部合併進 upstream main，
  無需再 bake。
- 產物為全靜態 binary，最終映像基於 `scratch`（約 13.5MB）。
- CI 自動建置並推送預編譯映像到 **`codeberg.org/lawlietr/redlib:latest`**。

## 部署方式

### 1. Docker（拉取預編譯映像，推薦）

```bash
# 若映像設為私有，先登入：docker login codeberg.org
docker pull codeberg.org/lawlietr/redlib:latest

docker run -d \
  --name redlib \
  -p 8080:8080 \
  -e DOMAIN=localhost \
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
      - DOMAIN=localhost
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

> 若想從原始碼本地建置（不等 CI），可用 repo 內的
> `redlib/docker-compose.yaml`：`cd redlib && docker compose up -d --build`
> （該 compose 以本 repo 為 context 執行 `docker build`）。

### 3. 從原始碼建置（手動 build）

```bash
docker build -f redlib/Dockerfile -t redlib .
docker run -p 8080:8080 -d --name redlib redlib

# 指定 Redlib 分支（預設 main）
docker build --build-arg REDLIB_BRANCH=main -f redlib/Dockerfile -t redlib .
# 指定上游 git 來源
docker build --build-arg REDLIB_SRC=https://github.com/redlib-org/redlib.git -f redlib/Dockerfile -t redlib .
```

## 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `PORT` | 8080 | 伺服器端口 |
| `DOMAIN` | localhost | 域名設定 |

## CI/CD

- 觸發：`*/Dockerfile` 變動或手動 "Run workflow"（可指定要 build 的 app）。
- 執行環境：本機自架 Forgejo Runner（`redlib` label），BuildKit + cargo cache mount（增量建置）。
- 推送目標：`codeberg.org/lawlietr/redlib:<tag>`（amd64）。
- 細節與故障排除：`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`。

## 專案資訊

- 原始碼：https://github.com/redlib-org/redlib
- Docker 個人實作，非官方專案
- License：本 repo 自有檔案（Dockerfile、腳本、設定）為 MIT；upstream redlib 保留 AGPL-3.0
