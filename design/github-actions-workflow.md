# GitHub Actions Workflow — ghcr.io 建置流程

> **狀態：已上線（2026-10-07）；repo 與 ghcr package 自 2026-10-21 起公開。** GitHub 遠端 `github.com/Lawlietr/redlib_docker` 已建立，
> `git remote add github ...` 已設好，`.github/workflows/build.yml` 由 push 到 `main` 自動觸發，
> 在 `ubuntu-latest` 原生編 amd64 並推 `ghcr.io/Lawlietr/redlib:latest`。
> 本地 Forgejo（`.forgejo/`，多架構 musl）仍是主要發佈路徑；兩條路徑的**來源內容必須一致**
> （都讀 `redlib-prs.txt`，見 `design/upstream-pr-bake.md`）。

## 1. 檔案位置
- Workflow：`.github/workflows/build.yml`（GitHub Actions 標準路徑）。
- 建構 / 推送腳本：`.github/scripts/build_and_push.sh`（`docker build -f Dockerfile` → `docker push`）。
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
- workflow 層級需要：

```yaml
permissions:
  contents: write
  packages: write
```

  `packages: write` 是**首次推送建立 package** 所需（只有 `contents: write` 時，push 到不存在的
  ghcr package 會 403）。
- 不需要額外 PAT / secret。
- **2026-10-21：GitHub repo 與 ghcr package 都已轉為 public**（使用者在 UI 手動翻轉；之前 repo private → package 默默繼承 private，容易誤判成「映像不存在」）。
  查證（全部**完全匿名**，用空的 `DOCKER_CONFIG`、不帶任何憑證）：
  - `GET /repos/Lawlietr/redlib_docker` → `private: false` / `visibility: public`。
  - `https://github.com/Lawlietr/redlib_docker/pkgs/container/redlib` → HTTP 200（之前是 404）。
  - `docker pull ghcr.io/lawlietr/redlib:latest` → 成功，`Digest: sha256:93606cc4b85ea4c3fe9b6a84401d95a7a8cb2e303cee4e35c5c5f9e6b8886f4e`，
    **與 Actions log（run `39534174002`，commit `15cc3c1`）裡的 digest 完全一致** → 公開的就是含 #592 那輪建置。
  - `docker manifest inspect -v` → entries=1、platform `linux/amd64`（仍是單架構、仍只有 `latest`）。
  - 跑起來複驗（同一映像、非 Codeberg 那份）：貼文頁 200、0 則留言 permalink 200、不存在的 sub 404（負 control）、
    頁面無 parse error 手語、container log 無 panic。
- 改公開**之前**的 symptom 留檔（日後若又拉不到，這組就是 visibility 被轉回 private 的訊號）：
  匿名 `docker manifest inspect` → `denied`；匿名 token flow → 403 `invalid token`；package 頁面 → 404。
  當時踩到的陷阱：用 git credential 裡那顆 `gho_` OAuth token（push code 用的）可以 `docker login ghcr.io`
  （Login Succeeded），但 manifest/tags 仍是 403 `permission_denied: The token provided does not match expected scopes`、
  `GET /user/packages` 403 `You need at least read:packages scope` → **能 login 不等於能 pull**；
  真的需要登入拉取時：`docker login ghcr.io -u <gh-user> -p <PAT read:packages>`。
- ⚠ **公開的代價：git 歷史全透明**。2026-10-21 已做健檢：全歷史 232 個 blob 掃 `gh[pousr]_…`、`github_pat_…`、
  `AKIA…`、`-----BEGIN … PRIVATE KEY-----` → **0 命中**；工作區只有 `.env.example`（內容全為註解/空值）；
  CI 只引用 `${{ secrets.CODEBERG_PAT }}`（Forgejo）與 `secrets.GITHUB_TOKEN`（Actions），PAT 本體在 CI secrets 內、
  不在 repo 裡。**日後 commit 前留意別把 `CODEBERG_PAT`、註冊 `uuid`/`token` 帶進 commit 或 `design/`**（AGENTS.md 同一要求）。

## 4. 推送目標 / tag
- `ghcr.io/${GITHUB_REPOSITORY_OWNER}/redlib:latest`（目前只 `latest`，沒有 `<git-sha>` tag —— 與 codeberg 版不同）。
  - ⚠ **owner 必須小寫**：`GITHUB_REPOSITORY_OWNER` 是 `Lawlietr`，但 registry repository name 只能小寫，
    `docker build -t ghcr.io/Lawlietr/redlib:latest` 會直接 `invalid tag … repository name must be lowercase`。
    腳本內以 `${GITHUB_REPOSITORY_OWNER,,}` 強制小寫 → 實際推送 `ghcr.io/lawlietr/redlib:latest`（與 codeberg 的 namespace 一致）。
    登入用的 username 則用原樣 account 名（`github.repository_owner`）。
- codeberg 版推 `codeberg.org/lawlietr/redlib:{latest,<git-sha>,amd64,arm64}`。

## 5. 架構：GitHub 端 amd64-only
GitHub 走 `docker build -f Dockerfile`，產出 **x86_64-unknown-linux-gnu 全靜態 glibc binary**，
在 `ubuntu-latest`（amd64）原生 build，**不需要** QEMU / buildx。

Codeberg/本地 Forgejo 端才是多架構（musl 原生交叉編譯，見 `design/multi-arch-build.md`）。

要在 GitHub 上也產 arm64（尚未做，TODO P3）的三條路：
1. **交叉編譯**：在 ubuntu-latest 裝 aarch64 musl 交叉工具鏈（Debian/Ubuntu **沒有**現成
   `aarch64-linux-musl-gcc`，要抓 musl.cc 的 toolchain tarball 或用 `cargo-zigbuild`），
   再沿用 `.forgejo/scripts/build_and_push.sh` 的 musl 邏輯 —— 與 12 機完全同構，最一致。
2. **QEMU + buildx**：`setup-qemu` + `buildx --platform linux/arm64`，QEMU 下編譯很慢（12 機的经验：QEMU 曾 1 小時以上）。
3. **arm64 public runner**：GitHub 的 arm64 hosted runner 需付費層級，目前不用。

## 6. Trigger
- `push` 到 `main` 且變更 `Dockerfile`、`redlib-prs.txt`、`.build/**`、`.github/**` 時觸發。
- `workflow_dispatch` 手動觸發（Actions → "Build container images" → Run workflow）。

## 7. 驗證步驟（每次改動後）
0. 注意：**新 repo 的首次 push 不會觸發 workflow**（GitHub 行為），要手動 `gh workflow run` 跑一次；之後 push 正常觸發。
1. `gh run list --repo Lawlietr/redlib_docker --limit 3` → 最新 run 是否 success。
2. `gh run view <id> --log` 裡應出現 5 行 `Merging PR #<n> -> <sha>`、無 `warning: PR ... head moved`。
3. `docker manifest inspect ghcr.io/lawlietr/redlib` 或 `ghcr.io/<owner>/redlib` → 確認 tag 存在、platform = linux/amd64。
4. 功能驗證清單見 `design/upstream-pr-bake.md` §7。

## 8. 與 codeberg 版的差異總覽
| 項目 | GitHub (`.github/`) | Codeberg / 本地 Forgejo (`.forgejo/`) |
|------|---------------------|----------------------------------------|
| runner | GitHub 託管 `ubuntu-latest` | 本機自架 `redlib`（Ubox-02 / 192.168.1.12） |
| 編譯方式 | `docker build -f Dockerfile`（glibc 靜態，host 原生） | `cargo` musl 交叉編譯 + `Dockerfile.pack`（見 multi-arch-build.md） |
| 架構 | amd64-only | amd64 + arm64（manifest list） |
| 登錄區 | `ghcr.io/{owner}/redlib:latest` | `codeberg.org/lawlietr/redlib:{latest,<sha>,amd64,arm64}` |
| 能見度 | **public**（2026-10-21 起：repo 與 package 都公開，匿名可拉） | public（Codeberg registry 公開拉取） |
| 認證 | `secrets.GITHUB_TOKEN` + `contents/packages: write` | `CODEBERG_PAT`（write:packages）secret |
| 來源內容 | 同一份 `redlib-prs.txt` bake | 同一份 `redlib-prs.txt` bake |
| guard | `if: github.server_url == 'https://github.com'` | 無（只在本地 Forgejo 跑） |
| 磁碟紀律 | 不需要（GitHub runner 磁碟大） | 需要（30GB host，disk_guard + prune） |
