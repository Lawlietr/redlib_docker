# Workflow 調整 — 登錄區網址、runs-on、建構工具

> **2026-09-18 已改完**（`.forgejo/workflows/build.yml` + `.forgejo/scripts/`，含 `disk_guard.sh` 與 trap prune），
> 待 `CODEBERG_PAT` secret 設好後推送（推送即觸發首次 build）。

## 背景
現行 `.forgejo/workflows/build.yml` 為 Codeberg 託管 runner（podman / `codeberg-medium` /
`registry.codeberg.org`）設計，與 12 機自架 Runner 不符。部署時需一併修正以下四點（外加認證與磁碟紀律）。

## 1. 登錄區網址（重要）
- 舊：`registry.codeberg.org/Lawlietr/containers:redlib`
- **問題**：`registry.codeberg.org` 現為 **NXDOMAIN**（本機與公共 DNS 1.1.1.1 均解析不到）。
- **新**：`codeberg.org/Lawlietr/redlib:latest`
- **查證**：`curl https://codeberg.org/v2/` 回
  `{"errors":[{"code":"UNAUTHORIZED"}]}`（HTTP 401）—— 這是標準 Docker Registry v2 的無身份回應，
  故 `codeberg.org` 即 Codeberg 現行登錄區。

## 2. runs-on
- 舊：`codeberg-medium`（Codeberg 託管 runner 的 label，自架 runner 沒有）。
- 新：`redlib`（對應本機 Runner label `redlib:host`）。

## 3. 建構 / 推送工具
- 舊：podman。
- 12 機：有 docker、無 podman → 改用 **docker**（`docker login` / `docker build` / `docker push`）。
- docker build/push 直接連本機 daemon（runner 容器掛 `/var/run/docker.sock`），不需 DinD。

## 4. 認證
- `docker login codeberg.org -u <user> -p <PAT>`。
- PAT 需 **write:packages** 範圍；Runner 自動生成的 token **推不上**登錄區。
- secret 名稱：`CODEBERG_PAT`，設於**本地 Forgejo** 的 redlib_docker repo secrets（workflow 在本地 Forgejo 執行）。
- **機敏，勿寫入版本庫。**

## 5. 磁碟紀律（12 機只有 10GB，必做）
見 `forgejo-runner-deployment.md` 的磁碟預算。workflow 內落地為：
1. **build 前守門**：`df --output=avail -k / | tail -1`，可用 < 6144000 KB（6G）→ 直接 fail（訊息：磁碟空間不足，中止 build）。
2. **push 後清理**：`docker image prune -a -f && docker builder prune -f`（builder stage、base pull、最終映像全清）。
3. **失敗路徑同樣清理**：用 `trap`（或 `if/else` 兩路徑都 prune）保證 build/push 失敗不殘留。
4. **不設持久 cache**：不加 BuildKit cache mount / sccache，每次 build 從零，磁碟可預測。

## 推送目標
- `codeberg.org/Lawlietr/redlib:latest`（tag 視需要調整）。
- 注意：此處推至 **public codeberg.org** 登錄區；**本地 Forgejo 的 registry 完全不使用**，
  編譯產物不會留在本地 Forgejo（它只當 git host + CI 調度）。
- 12 機上 build 後的本地映像亦於 push 後立即 prune（紀律 2）→ 產物只存在 codeberg.org。

## 與 `.github/workflows/build.yml` 的關係
- `.github/` 那份是 GitHub ghcr.io 的 guarded 備援（`if: github.server_url == 'https://github.com'`），
  推到 `ghcr.io`，**不用動**。
- 只有 `.forgejo/workflows/build.yml` 需要上面四項修正。

## 6. codeberg.org 連線 workaround（12 機專用，2026-09-18）

### 症狀
- 12 機的 **docker daemon（Go 1.26）連 `codeberg.org` 一律 `unexpected EOF`**：
  TLS 握手成功、server 回資料後連線被邊緣直接砍（tcpdump 證實 RST/FIN）。
- 同機 `curl` 與独立 Go 客戶端（1.26/1.27）直連 codeberg 都正常；拉 docker.io 也正常。
  → 問題限定在「docker daemon 對 codeberg.org」這條路徑（邊緣對其連線行為有問題，可回報給 codeberg）。
- 曾試過無效：關 IPv6（`net.ipv6.conf.all.disable_ipv6=1`，本機 v6 路徑本來就壞）、
  `GODEBUG=tlsmlkem=0`、`GODEBUG=http2client=0`、改 UA。
- 另觀測：對 `/v2/token` 帶 **Basic auth** 的請求會被邊緣砍（h2 回 `stream CANCEL`、
  h1 回 `unexpected EOF`）；無 auth 的 ping 正常。curl 帶同樣 Basic auth 反而正常。
  真實 PAT 的 login 行為待驗證（若有效憑證也被砍，需再研究）。

### Workaround：本機反向代理 `cbgproxy`
利用 daemon 的 https→http 探測回落 + `/etc/hosts` 導流：

1. `/etc/hosts`：`127.0.0.1 codeberg.org`
2. `cbgproxy`（Go 反向代理，systemd 服務）：
   - 聽 `127.0.0.1:80`，轉發 `https://codeberg.org`（直撥邊緣 IP `217.197.84.140`，SNI=`codeberg.org`）。
   - `ModifyResponse` 把 `WWW-Authenticate` 的 Bearer realm 由 `https://` 改寫為 `http://`，
     讓 token 交換也留在代理內。
   - 代理本體的 Go 客戶端連 codeberg 正常（已證實）。
3. daemon 流程變成：`https://codeberg.org`（127.0.0.1:443 拒連）→ 回落
   `http://codeberg.org`（127.0.0.1:80 代理）→ 代理 TLS 轉發上游。

### 12 機上的檔案
- 原始碼：`/opt/cbgproxy/main.go`（副本存於 `design/cbgproxy-main.go`，無機敏資訊）
- 二進位：`/opt/cbgproxy/cbgproxy`（Go 1.26.8 編譯）
- 服務：`/etc/systemd/system/cbgproxy.service`（`Restart=always`，已 enable）
- 工具鏈：`/tmp/g126/go`（Go 1.26.8，重建代理用；/tmp 重開機會清，需時重裝）

### 注意
- `/etc/hosts` 導流只影響 12 機 host 層對 `codeberg.org` 的解析（containers 用自己的 DNS，不受影響）。
- 若 codeberg 邊緣 IP 變更（非固定），需更新代理內的 `upstreamIP`。
- 此 workaround 與 workflow 本身無關；CI 側完全無感。

### 6.1 後續發現與修正（2026-09-18 晚些）
1. **Basic auth 砍連線是「間歇窗口」**：`/v2/token` 帶 Basic auth 的請求（無論 Go 客戶端
   還是 curl）會在數分鐘的「砍窗口」內一律被邊緣取消（h2 `stream CANCEL` / h1 `unexpected EOF`）；
   窗口過去後全部恢復。窗口疑似與失敗認證嘗試的累積有關。
   → 代理改為**攔截 `/v2/token`、以 curl 子程序上游 + 5 次重試**；
   workflow 的 login step 再加**6 次整輪重試（backoff 15–75s）**跨窗口。
2. **runner 容器 job user 沒有 docker socket 權限 → docker CLI 用戶端 fallback**：
   job 以 UID 1000 執行，對 `/var/run/docker.sock`（root:990）無權限；`docker login` 連不上
   daemon 時會**改在 CLI 端自己對 registry 驗證**（log 的 endpoint 結構與 daemon 不同、daemon
   journal 無記錄），直連 codeberg 真實邊緣 → 必然 `unexpected EOF`，完全繞過 cbgproxy。
   → 重建 runner 容器時加 `--group-add 990`（host docker 群組 GID）。
   重建指令注意：image 的 ENTRYPOINT 是 dumb-init，CMD 需完整給
   `/bin/forgejo-runner daemon -c /home/runner/.config/forgejo/runner/config.yaml`。
3. 驗證路徑（12 機）：`docker exec -u 1000:1000 forgejo-runner docker login ...` 應走
   host daemon（journal 出現 3 欄位 endpoint）→ https 拒連 → http cbgproxy → token via curl。
4. **真正的根本原因：login 用錯 username（2026-09-18 定案）**：workflow 原本用
   `${{ github.repository_owner }}` 當 `docker login --username`——但 registry 是
   **codeberg.org**，該 owner 是 **`Lawlietr`**；本地 Forgejo 的 owner 是 `lawliet`。
   每次 login 都是 401（失敗認證），不斷觸發/延長 codeberg 邊緣的砍連線窗口，
   與「重試不夠多」無關。→ login step 改用明確的 `CODEBERG_USERNAME: Lawlietr`。
   另：`CODEBERG_PAT` secret 須為 **repo-level**（user-level 在 v15 的 API 有 500 問題）；
   本版本 API 建 secret 的欄位名是 `data`（非 `secret_value`）。
   驗證（12 機）：`curl -u lawlietr:<PAT> http://codeberg.org/v2/token?...` → 200 且
   `UserID` 非 -1；`docker login codeberg.org --username lawlietr` → Login Succeeded。
5. **buildx / BuildKit（2026-09-18）**：Dockerfile 用 `RUN --mount=type=cache`（cargo registry + target
   cache），需要 BuildKit。runner 容器（Alpine docker-cli 29.5.3）沒有 buildx plugin，
   `DOCKER_BUILDKIT=1 docker build` 會報「BuildKit is enabled but the buildx component is missing」。
   → 容器內 `apk add docker-cli-buildx`（0.34.1）後 **commit 成 `forgejo-runner-redlib:13.1.1`**，
   compose 改用該 tag 並補 `group_add: ["990"]`（把之前重建時的 socket 群限固化進 compose）。
   `build_and_push.sh` 內已 `export DOCKER_BUILDKIT=1`。
6. **push 命名空間**：`build_and_push.sh` 的 image tag 不可用 `GITHUB_REPOSITORY_OWNER`
   （本地 Forgejo owner = `lawliet`）；Registry 是 codeberg.org，命名空間為 Codeberg 帳號
   `Lawlietr`（script 內已定 `CODEBERG_USER=Lawlietr`）。
7. **Bake chain 退役（2026-09-18）**：Dockerfile 原來的 PR merge 鏈（#506/#509 baseline +
   #521/#560/#539/#549，`--depth 300` + `-X ours`）已退役。原因：
   - upstream main 已把 #506/#521/#560/#539/#549 全部 merge 進去（至 `8167e00`），
     直接 build `main` 就包含全部改動（GitHub API 的 `state=open` 是過期快取，
     以 git ancestry 為準：`git merge-base --is-ancestor prN main`）。
   - 舊鏈用 pr509（hyper-tls，pre-wreq）當 base，`-X ours` 保留的是 pr509 的
     `client.rs`/`Cargo.toml`/`Cargo.lock`，不是 main 的 wreq 版；pr509 的舊
     `Cargo.lock` 撞上新 crates.io 的 checksum（`openssl-probe v0.1.6`），
     `cargo fetch --locked` 直接失敗。
   - #509（hyper-tls）被 main 的 wreq 遷移（#544）取代，不再需要 bake。
   現在 Dockerfile 就是 `git clone --depth 1 --branch main` + `cargo build --release --locked`。

## 7. Builder 從 alpine/musl 改 glibc 靜態建置（2026-09-18 定案）

**症狀**：CI build 掛在 `boring-sys2`（wreq 的 BoringSSL）build script：
`failed to find tool "c++"` / `Dynamic loading not supported`（bindgen dlopen libclang）。

**根因**：musl 靜態編譯的 build script 無法 `dlopen` libclang（bindgen 0.72 固定用
`runtime` feature）；alpine 也沒有 musl-tools（glibc 下交叉編譯）與
`x86_64-linux-musl-g++`。musl 路線無解。

**定案**：builder 改 `rust:1.98-slim-bookworm`（glibc，bindgen 的 dlopen 正常），
build deps：`build-essential cmake clang libclang-dev perl pkg-config git ca-certificates`。
產出**全靜態 glibc binary**，release stage 維持 `scratch`：

```
cargo rustc --release --locked --bin redlib --target-dir ... -- \
    -C target-feature=+crt-static \
    -C relocation-model=static \
    -C link-args=-static
```

**坑**（實測驗證）：
1. 靜態 flag **只能**透過 `cargo rustc -- ...` 給最終 crate。放進
   `.cargo/config.toml` 的 `[target.x86_64-unknown-linux-gnu] rustflags`（或 RUSTFLAGS env）
   會連 proc-macro crates 一起套用 → `cannot produce proc-macro ... does not support
   these crate types`（cargo 把 host triple 的 target section 當成 cross target）。
2. glibc 靜態 CRT 不兼容 PIE → 缺 `-C relocation-model=static` 會在 link 階段
   掛在 `crtbeginT.o`。
3. `link-args=-static` 用 glibc 自帶的 `libc.a`（bookworm 的 glibc 套件就有，
   不需額外套件）。BoringSSL 是 staticlib、redlib 不靠 OpenSSL/NSS，全靜態可行。

**驗證（2026-09-18）**：`docker build` 全綠；binary 13.3MB、`readelf -d` 無
dynamic section；scratch 映像 13.5MB；容器內 `Redlib 0.36.0` 啟動並對
`/` 回 HTTP 200（實際抓到 Reddit 內容）。

**磁碟影響（12 機 10GB）**：bookworm builder 映像層比 alpine 大（~2.5GB vs ~1.6GB），
但 build 完 `docker image prune -a` 會清掉；持久的是 BuildKit cache mounts
（registry + target，增量編譯用，~3–4GB）。若磁碟吃緊：`docker builder prune`。
