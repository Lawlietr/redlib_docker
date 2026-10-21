# GitHub Actions Workflow — ghcr.io 建置流程

> **狀態：已上線（2026-10-07）；repo 與 ghcr package 自 2026-10-21 起公開；同日補上 arm64 與 `<git-sha>` tag，
> 並從同日成為主要發佈路徑。** GitHub 遠端 `github.com/Lawlietr/redlib_docker` 已建立，
> `git remote add github ...` 已設好，`.github/workflows/build.yml` 由 push 到 `main` 自動觸發，
> 走兩個 build job（amd64 跑 `ubuntu-latest`、arm64 跑 `ubuntu-24.04-arm`）+ 一個 manifest job，
> 推 `ghcr.io/lawlietr/redlib:{latest,<git-sha>,amd64,arm64}`（四個 tag、兩架構）。
> 本地 Forgejo（`.forgejo/`，多架構 musl）**保留但只手動觸發**（2026-10-21 移除 `push` trigger），
> 作為 GitHub Actions 不可用時的緊急備援；`codeberg.org/lawlietr/redlib` 的 tag
> **由同一條 GitHub CI 的 `mirror-codeberg` job 鏡像維護**（見 §9），不再靠 12 機重新建置。兩條路徑的**來源內容必須一致**（都讀 `redlib-prs.txt`，見 `design/upstream-pr-bake.md`）。
> 本地 `docker build` + 起容器也是支援的測試途徑（只產本機架構；命令與 smoke 清單見 README 的「本地編譯與測試」節）。
> 作業層級以 `concurrency: ghcr-publish` 串行，避免 manifest merge 混到不同 commit 的兩個架構。

## 1. 檔案位置
- Workflow：`.github/workflows/build.yml`（GitHub Actions 標準路徑；matrix 兩個 build job + 一個 manifest job）。
- 建構 / 推送腳本：`.github/scripts/build_and_push.sh`（吃 `ARCH`：`docker build -f Dockerfile --platform linux/$ARCH` → `docker push :$ARCH`）
  與 `.github/scripts/merge_manifest.sh`（`docker buildx imagetools create` 合併出 `:latest` 與 `:<git-sha>`）。
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
- **兩個架構、四個 tag**（與 codeberg 版同名同義）：`ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/redlib:{latest,<git-sha>,amd64,arm64}`。
  - `:amd64` / `:arm64` —— 各 build job 自己推的單架構映像。
  - `:latest` / `:<git-sha>` —— `.github/scripts/merge_manifest.sh` 用 `docker buildx imagetools create`
    合併出的**多平台 manifest list**（`imagetools` 是純 registry 側操作、不執行目標代碼，所以合併 job
    跑在 amd64 runner 就够）。git sha 用 `git rev-parse --short HEAD`，**與 `.forgejo/scripts/build_and_push.sh`
    同一算法** → 同一 commit 在兩個 registry 上的 tag 字串一致，使用者换 registry 不用改 tag 惯例。
    （2026-10-21 之前 ghcr 只推 `latest`，那是兩邊不一致的地方，已補齊。）
  - ⚠ **owner 必須小寫**：`GITHUB_REPOSITORY_OWNER` 是 `Lawlietr`，但 registry repository name 只能小寫，
    `docker build -t ghcr.io/Lawlietr/redlib:latest` 會直接 `invalid tag … repository name must be lowercase`。
    兩支脚本都以 `${GITHUB_REPOSITORY_OWNER,,}` 強制小寫 → 實際推送 `ghcr.io/lawlietr/redlib/...`（與 codeberg 的 namespace 同形）。
    登入用的 username 則用原樣 account 名（`github.repository_owner`）。
  - namespace 由 `$GITHUB_REPOSITORY_OWNER` 推導，**fork 不改任何檔案**就會推到自己的 namespace。
- codeberg 版推 `codeberg.org/lawlietr/redlib:{latest,<git-sha>,amd64,arm64}`。

## 5. 架構：兩邊都是雙架構，但編法不同
- **GitHub 端**：`docker build -f Dockerfile --platform linux/<arch>`，在**對應架構的 runner 上原生 build**
  （amd64 → `ubuntu-latest`；arm64 → `ubuntu-24.04-arm`），產出 **x86_64 / aarch64 全靜態 glibc binary**
  （`+crt-static`）。不用 QEMU、不用交叉工具鏈。
- **Codeberg / 本地 Forgejo 端**：musl 原生交叉編譯 + `Dockerfile.pack`（見 `design/multi-arch-build.md`）。
  此處的 musl 是「x86 主機要交叉出 arm64」的實作手段，**不是產品承諾**；只有那條備援路被手動跑時才會碰到發佈物。
- ⚠ 兩條路的 **binary 編譯來源不同**（musl 交叉 vs glibc 原生靜態）；
  跨 registry 比對時比 tag 與行為。**例外（2026-10-21 起）**：codeberg 的 tag 若是被 §9 的鏡像复制過去的，
  內容與 digest **完全相同**；只有手動跑 `.forgejo/` 那條備援路會讓 digest 分岔。

### arm64 的三條路（2026-10-21 選第 3 條，已上線）
1. **交叉編譯**（ubuntu-latest 上装 aarch64 musl 交叉工具鏈，沿用 `.forgejo/` 的 musl 邏輯）——
   與 12 機同構、產物形態與 codeberg 版一致，但要維護交叉環境（`CXX_*`/`AR_*`/`BINDGEN_EXTRA_CLANG_ARGS` 那整套）。
2. **QEMU + buildx**：`setup-qemu` + `buildx --platform linux/arm64`，QEMU 下編譯很慢（12 機的經驗：QEMU 曾 1 小時以上）。
3. **原生 arm64 hosted runner**（`ubuntu-24.04-arm`）：**2025-08-07 起 public repo 免費 GA**（2026-01-29 起 private 也能用）。
   本 repo 已公開 → 直接可用；實測 arm64 build job 全程約 4 分鐘（與 amd64 job 並行）。代價：arm 端產物變成
   **glibc 靜態**（與 codeberg 的 musl 產物不同形，但都跑在 `scratch`、行為一致）。

**2026-10-21 上線證據**（commit `d572b2e`，run `39543407871`，build (amd64) / build (arm64) / manifest 三 job 皆 success）：
- 匿名 `GET /v2/lawlietr/redlib/tags/list` → `["latest","arm64","amd64","d572b2e"]`。
- `latest` 與 `d572b2e` 都是 `manifest.list.v2`，entries = `linux/amd64` + `linux/arm64`。
- 将 arm64 映像裡的 `/redlib` `docker cp` 出來看 ELF：`ELF 64-bit LSB executable, ARM aarch64, statically linked`、
  `Machine: AArch64`、**無 INTERP、無 dynamic section**（11,819,336 bytes）→ 形状與 amd64 版一致。
- ❗ **ghcr 版 arm64 尚未在真 arm64 硬體上執行過**：本機 x86_64 且無 qemu binfmt（`tonistiigi/binfmt --install arm64`
  在此主機無效，`docker run --platform linux/arm64` 會 `exec format error`）。上面是**靜態證據**，不代替執行驗證；
  需在真 arm64 機器上跑 `docker run --rm -p 8080:8080 ghcr.io/lawlietr/redlib:latest` 才算閉環（見 TODO）。

## 6. Trigger
- `push` 到 `main` 且變更 `Dockerfile`、`redlib-prs.txt`、`.build/**`、`.github/**` 時觸發。
- `workflow_dispatch` 手動觸發（Actions → "Build container images" → Run workflow）。

## 7. 驗證步驟（每次改動後）
0. 注意：**新 repo 的首次 push 不會觸發 workflow**（GitHub 行為），要手動 `gh workflow run` 跑一次；之後 push 正常觸發。
1. `gh run list --repo Lawlietr/redlib_docker --limit 3` → 最新 run 是否 success。
2. `gh run view <id> --log` 裡應出現 5 行 `Merging PR #<n> -> <sha>`、無 `warning: PR ... head moved`。
3. 匿名 `docker manifest inspect ghcr.io/lawlietr/redlib:latest`（及 `:<git-sha>`）→ **應看到兩個 entries**
   （`linux/amd64` + `linux/arm64`）；只有 1 個 entries 就是某個 matrix job 沒成功（看是哪一個 arch 分支）。
4. 功能驗證清單見 `design/upstream-pr-bake.md` §7。

## 8. 與 codeberg 版的差異總覽
| 項目 | GitHub (`.github/`) | Codeberg / 本地 Forgejo (`.forgejo/`) |
|------|---------------------|----------------------------------------|
| runner | GitHub 託管 `ubuntu-latest` + `ubuntu-24.04-arm`（兩個 job，各自原生） | 本機自架 `redlib`（Ubox-02 / 192.168.1.12） |
| 編譯方式 | `docker build -f Dockerfile`（glibc 靜態，host 原生） | `cargo` musl 交叉編譯 + `Dockerfile.pack`（見 multi-arch-build.md） |
| 架構 | **amd64 + arm64**（manifest list，2026-10-21 起） | amd64 + arm64（manifest list） |
| 登錄區 | `ghcr.io/{owner}/redlib:latest` | `codeberg.org/lawlietr/redlib:{latest,<sha>,amd64,arm64}` |
| 能見度 | **public**（2026-10-21 起：repo 與 package 都公開，匿名可拉） | public（Codeberg registry 公開拉取） |
| 認證 | `secrets.GITHUB_TOKEN` + `contents/packages: write` | `CODEBERG_PAT`（write:packages）secret |
| 來源內容 | 同一份 `redlib-prs.txt` bake | 同一份 `redlib-prs.txt` bake |
| guard | `if: github.server_url == 'https://github.com'` | 無（只在本地 Forgejo 跑） |
| 磁碟紀律 | 不需要（GitHub runner 磁碟大） | 需要（30GB host，disk_guard + prune） |

## 9. 鏡像到 codeberg.org（`mirror-codeberg` job，2026-10-21 新增）

**為什麼需要**：編譯工作改到 GitHub Actions 之後，12 機不再自動建置，但
`codeberg.org/lawlietr/redlib` 的 tag 仍要跟著更新。做法是 **registry 側的 copy**，不是重建：

- 腳本：`.github/scripts/mirror_to_codeberg.sh`，job `mirror-codeberg`（`needs: manifest`）。
- 指令：`docker buildx imagetools create -t codeberg.org/lawlietr/redlib:<tag> ghcr.io/lawlietr/redlib:<tag>`，
  覆蓋 `latest`、`<git-sha>`、`amd64`、`arm64` 四個 tag（含 manifest list 的 child 引用）。
- 特性：**不跑 cargo、不用 QEMU**，只搬 ~13MB 的 blob；因為全部 content-addressed，
  **鏡像後的 digest 與 ghcr 一致**（腳本结尾會比對 child digest 並打印）。
- 認證：需要 GitHub repo secret **`CODEBERG_PAT`**（Codeberg PAT，`write:packages`）。
  username 用帳號原樣 `Lawlietr`，registry 路径是小寫 `lawlietr`（與 `.forgejo/` 那條路同一個不對稱）。
  登入帶 6 次退避重試（Codeberg registry 邊緣偶發會掐 auth 請求）。
- **缺 secret 就 exit 1**，不會靜默略過 —— 這是刻意設計，避免「鏡像悄悄不更新」。
- ⚠ 若有人**手動**跑 `.forgejo/workflows/build.yml`（它自己的 musl 交叉產物），它會把這四個 tag 指向不同的 digest；
  下一次 GitHub 建置會再把鏡像蓋回來。musl 已不是產品線（§11），不該為它保留專用 tag。
- 對 fork 的影響：鏡像目標是寫死的 `codeberg.org/lawlietr/redlib`（我們的 namespace），
  fork 若沒有對應 secret 就會在該 job 失敗；fork 要嘛加自己的 secret、要嘛把該 job 註解掉。

## 10. 發佈前的 `smoke` job（2026-10-21 新增）

順序：`build` → `manifest` → `smoke`（`needs: manifest`）→ `mirror-codeberg`（`needs: smoke`）。
鏡像以煙測為前提，**壞映像不會流到 Codeberg**。

腳本：`.github/scripts/smoke_test.sh`，四步

1. `docker cp` 把 `:amd64` 裡的 `/redlib` 抓出來 `file` + `readelf -d`：**必須是全靜態**（有 `NEEDED` 就直接 fail，
   因為 `scratch` 上沒有 loader）。⚠ 不要想用 `--help` 探測 —— **redlib 不收任何 CLI 參數**，餵它 `--help` 只會得到
   `error: unexpected argument found`（2026-10-21 實測），設定一律來自環境變數。
2. 起容器打 `/`（最多輪詢 8 次）：必須 200，且 body ≥ 20KB（錯誤頁通常遠小於此）。
3. 打 `/r/gaming`、`/r/AskReddit/top`：強迫容器內做 **DNS 解析 + 出網 HTTPS**。這是重點 —— 靜態 glibc 在
   `scratch` 裡沒有 `libnss_*`，理論上 `getaddrinfo` 會失敗；2026-10-21 實測（amd64）沒發生，但要由 CI 持續
   守著，而不是靠線上發現。
4. arm64 側的**確定性**閘門：`docker create --platform linux/arm64` + `docker cp` 取出的 binary 必須是
   `ARM aarch64` 且全靜態（不需 qemu、不需模擬）。若 runner 上**恰好**有 `qemu-aarch64` binfmt，會额外試著真的
   起 arm64 容器打 `/`，失敗只 `::warning::`。**功能級 arm64 驗證仍需真硬體**（qemu 使用者模式不等於樹莓派），
   見 TODO 的 P2。

判定尺度：
- `>=500` 或完全無回應 → **fail**，並附 40 行 container log。
- reddit 回 **403/429** → `::warning::`，**不 fail**：GitHub runner 的機房 IP 會被 reddit 限流，但 DNS 與往返
  已證明成功，而這兩項才是本 job 的目的。
- log 出現 `temporary failure in name resolution` / `failed to lookup` / `resolve` → **fail**，訊息直接點名
  「靜態 binary 在 scratch 無法做 DNS」。

基線（2026-10-21 本機 x86_64 完整跑過一次 `smoke_test.sh`，exit 0）：amd64 binary `statically linked`、arm64 binary
`ARM aarch64 ... statically linked`、`/` 200（54~61KB，首次輪詢常因容器還沒 listen 而 000）、`/r/gaming` 200 79,425B、
`/r/AskReddit/top` 200 38,009B、log 無解析器錯誤。

## 11. musl 退場為產品線，只留作備援路的實作細節（2026-10-21 決策）

**決策**：`.forgejo/` 的 musl 交叉建置**保留 workflow 與 runner**，但 musl **不再作為對外承諾的產物格式**；
不新增 `-musl` 之類的專用 tag，文件也不再宣稱「Codeberg 是 musl 版」。

**依據（同日實測，x86_64 同一台機器）**

| 項目 | ghcr glibc `+crt-static` | Codeberg 舊 musl 版（tag `15cc3c1`） |
|---|---|---|
| `readelf -d` NEEDED | 0（全靜態） | 0（全靜態） |
| 映像大小 | 13.5MB | 13.2MB |
| `/` | 200 61,422B | 200 61,422B |
| `/r/AskReddit/top` | 200 38,009B | 200 38,009B |
| `/r/gaming`（DNS + 出網） | 200 79,424B，無解析器錯誤 | 200 79,424B，無解析器錯誤 |

- 靜態 glibc 在 `scratch` 的 NSS/DNS 疑慮**沒有發生**，所以 musl 最後的技術理由消失；大小也沒有差異可言。
- musl 當初存在的理由是「在 x86_64 的 12 機上交叉出 arm64」；GitHub 提供**免費原生 arm64 hosted runner** 之後，
  這個需求本身消失。留著 musl 產品線只剩維護成本：musl-cross-make 工具鏈、`CC_/CXX_/AR_/BINDGEN_EXTRA_CLANG_ARGS`
  那組 env（見 `design/multi-arch-build.md`），以及與鏡像搶 tag 造成的 digest 分岔。
- **不做**的事：不把 `Dockerfile` 改成 musl（`design/forgejo-runner-workflow.md` §7 已記錄 alpine/musl 路線在
  bindgen/libclang 上無解）、不為 musl 保留平行 tag、不在 README 的 Tags 表宣稱 musl。
- 舊的 musl tag 在 Codeberg 仍拉得到（`15cc3c1`、`48bdbed`、`7489ef4`、`74cc5f8`），pin 過的人不會壞；
  但 `latest`/`<git-sha>`/`amd64`/`arm64` 現在由鏡像持有，內容等於 ghcr。
