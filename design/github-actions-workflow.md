# GitHub Actions Workflow — ghcr.io 建置流程

> **狀態：workflow 已寫好，待 GitHub 遠端。** 目前 repo 只在本地 Forgejo 與 Codeberg，
> GitHub 遠端尚未建立。workflow 已放入 `.github/workflows/build.yml`，等使用者加入
> GitHub 遠端並 enable Actions 後即可自動跑。實作要領記錄如下。

## 1. 檔案位置
- Workflow：`.github/workflows/build.yml`（GitHub Actions 標準路徑）。
- 建構 / 推送腳本：`.github/scripts/build_and_push.sh`。
- 與 codeberg 版 `.forgejo/workflows/build.yml` 並存，各自推到各自的登錄區。

## 2. 為什麼要 guard（重要）
repo 同時掛在本地 Forgejo 與 Codeberg。這兩個 runner 也會讀到 `.github/workflows/build.yml`，
但沒有 GitHub 認證、也推不到 ghcr.io。所以 job 內加：

```yaml
if: ${{ github.server_url == 'https://github.com' }}
```

- 在 github.com 上：`github.server_url` == `https://github.com` → **執行**。
- 在 Codeberg / 本地 Forgejo 上：server_url 不同 → **跳過**（文件照讀，job 不跑）。

## 3. ghcr.io 認證
- 用 Actions 自動生成的 `secrets.GITHUB_TOKEN`，`username` 用 `${{ github.repository_owner }}`。
- **必須**在 workflow 層級開 `permissions: contents: write`，ghcr.io 推送才允許：

```yaml
permissions:
  contents: write
```

- 不需要額外的 PAT / secret（`GITHUB_TOKEN` 即可）。若日後要推到 org 層級的 ghcr.io，
  才需要額外設定 org membership 權限或用 PAT（`cr:write` scope）。

## 4. 推送目標 / tag
- `ghcr.io/${GITHUB_REPOSITORY_OWNER}/redlib:latest`
- 與 codeberg 版對稱：codeberg 推 `codeberg.org/lawlietr/redlib:latest`，GitHub 推 `ghcr.io/{owner}/redlib:latest`。
- tag 用 `latest`（視需要再加 version tag）。

## 5. 架構：amd64-only（重要）
Dockerfile 產出的是 **x86_64-unknown-linux-gnu 全靜態 glibc binary**，沒有 arm64 cross-compile。
所以 GitHub 版與 codeberg 版一樣只用 `--platform linux/amd64`，plain `docker build` 即可，
**不需要** QEMU / buildx（在 linux/amd64 runner 上原生 build）。

- 若日後要多平台（amd64 + arm64）：
  1. 先改 Dockerfile 支援 arm64 cross-compile（`--target aarch64-unknown-linux-gnu` + qemu）。
  2. 再加 `docker/setup-qemu-action` + `docker/setup-buildx-action`，
     `build_and_push.sh` 改 `docker buildx build --platform ... --push`。
  3. 目前**不做**（binary 是 amd64 static，強上 arm64 會產出錯的 image）。

## 6. Trigger
- `push` 到 `main` 且變更 `Dockerfile` 或 `.github/**` 時觸發。
- `workflow_dispatch` 手動觸發。

## 7. 待辦（等 GitHub 遠端）
1. 加入 GitHub 遠端（`git remote add github ssh://git@github.com/{owner}/redlib_docker.git`）。
2. 在 GitHub repo → Settings → Actions → General，確認 Actions 已啟用，
   並確認 workflow permissions（`contents: write` 已寫在 workflow 內，通常夠用）。
3. 推一次（或手動 workflow_dispatch）驗證 build + push 到 ghcr.io 成功。
4. 驗證後把 TODO.md 的 GitHub Actions 項目標為完成。

## 8. 與 codeberg 版的差異總覽
| 項目 | GitHub (`.github/`) | Codeberg (`.forgejo/`) |
|------|---------------------|------------------------|
| runner | GitHub 託管 `ubuntu-latest` | 本機自架 `redlib:host` |
| 登錄區 | `ghcr.io/{owner}/redlib:latest` | `codeberg.org/lawlietr/redlib:latest` |
| 認證 | `secrets.GITHUB_TOKEN` + `contents: write` | `CODEBERG_PAT`（write:packages）secret |
| 架構 | amd64-only（原生 build） | amd64-only（host 原生 build） |
| guard | `if: github.server_url == 'https://github.com'` | 無（只在本地 Forgejo 跑） |
| 磁碟紀律 | 不需要（GitHub runner 磁碟大） | 需要（10GB host，disk_guard + prune） |
