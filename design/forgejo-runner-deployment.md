# Forgejo Runner Docker 部署 — 實施要領（12 機，10GB 磁碟）

> **2026-09-18 已部署完成**：Runner（`forgejo-runner-redlib:13.1.0`）在 **192.168.1.12（Ubox-02）**
> 上線，`labels: [redlib]`，poller 正常、註冊成功（`declared successfully`）。
> **12 只有 10GB 磁碟，磁碟紀律是本方案核心。**
> 產出的映像**只推送至 Codeberg 登錄區**（`codeberg.org`），本地 Forgejo 與 12 都不保留編譯產物（見下）。
> 待辦：首次在 Forgejo 設 `CODEBERG_PAT` secret → 推送 workflow 修正 → 首次 build 驗證。
> cargo cache 已定案 **Tier 2**（registry + target 雙 cache mount，增量編譯）。

## 目標
12 上的 Forgejo Runner 執行 `.forgejo/workflows/build.yml`：docker build redlib → 推送 `codeberg.org/Lawlietr/redlib:latest` → **本地清理**。

## 已查證環境（12，唯讀）
- Ubox-02，Ubuntu 24.04.5，x86_64，**5C / 10G RAM**（可用 ~9.9G）。
- **磁碟 10GB（zfs subvol），已用 2.6G、剩 7.5G**。
- Docker 29.8.1，**完全乾淨：0 映像、0 容器**。無 podman/cargo/node（只有 docker + git）。
- outbound 可達：docker.io、data.forgejo.org、codeberg.org；到 Forgejo `http://192.168.1.124:3000` 13ms。
- 無 komodo（124 的 komodo 管理不涵蓋 12）→ 用**單機 compose 目錄**管理。
- runner 鏡像源：`data.forgejo.org/forgejo/runner`，最高 `13.1.0`（runner 版本獨立於 Forgejo；Forgejo 15 文件示範即 `:13`）。

## 部署（已執行）：單機 compose 目錄
目錄：`/opt/forgejo-runner/`（12 上）
- `Dockerfile`：`FROM data.forgejo.org/forgejo/runner:13.1.0`（**Alpine 3.24.1**，runner 本体 45.2MB），
  `USER root` → `apk add --no-cache nodejs npm git docker-cli ca-certificates` → `USER 1000:1000`。
  擴建後映像 **155MB**。**不需 rust/cargo**——redlib 的 cargo build 在 `redlib/Dockerfile` builder stage 容器內。
- `config/config.yaml`：`labels: ["redlib:host"]`、`capacity: 1`、`server.connections.forgejo`
  （`url: http://192.168.1.124:3000`、uuid、**`token_url: file:/run/runner-secrets/token.txt`**——token 走獨立檔，設定檔本身不含金鑰）。
- `credentials/token.txt`：註冊 token（**機敏，600，owner uid 1000，不進 git**）。
- `compose.yaml`：容器 `forgejo-runner`，`command: ["/bin/forgejo-runner", "daemon", "-c", ...]`，
  `restart: unless-stopped`；volumes：`config.yaml`（ro）、`credentials/`→`/run/runner-secrets`（ro）、
  `data/`→`/home/runner`、`/var/run/docker.sock`（docker build/push 直用 host daemon，免 DinD）。
- `data/`（uid 1000）：`.runner` 註冊狀態 + job workspace（很小；docker build 產物在 docker 層，不在此）。
- label：`redlib:host`（host label 的 step 跑在 runner 容器自身 → 工具鏈裝在鏡像裡）；
  workflow 的 `runs-on: redlib`。
- 註冊：**v13.1.0 的 `register` 副命令已 deprecated**——只需 `daemon`，它會從 config 自動註冊
  （日誌 `declared successfully` 即成功）。

### 部署踩過的坑（照此文件部署時直接避開）
1. 映像預設 **USER 1000**（非 root）→ Dockerfile 裡 `apk add` 前必須 `USER root`。
2. entrypoint 是 `dumb-init` → compose 的 `command` 要寫**完整 binary 路徑** `/bin/forgejo-runner`，
   只寫 `daemon` 會被當成可執行檔名。
3. token 檔若 root:600 → 容器（uid 1000）讀不到，開機報 `permission denied`；要 chown 給 1000。
4. `data/` 目錄要先建好並 chown 1000:1000，否則容器寫 `.runner`/workdir 會失敗。

## 磁碟紀律（10GB，核心）
### 預算
| 項目 | 大小 | 性質 |
|---|---|---|
| 既有系統 | 2.6G | 常駐 |
| runner 映像（base 45MB + 擴建 155MB） | ~0.2G | 常駐（實測） |
| runner data/workspace | <0.1G | 常駐（小） |
| build 瞬時：rust:alpine base pull | ~1.0G | **build 期間** |
| build 瞬時：apk + git clone（depth 300 + 6 PR） | ~0.2-0.3G | **build 期間** |
| build 瞬時：cargo fetch（~450 crates） | ~0.5G | **build 期間** |
| build 瞬時：cargo build release target | ~2.5-3.5G | **build 期間** |
| 最終映像（scratch + 靜態二進位） | ~0.04G | push 後即刪 |

**build 峰值 ≈ 4.5-5.5G**；剩 7.5G → 峰值後約剩 2-3G，可行但有紀律要求：

### 紀律（寫進 workflow 與腳本）
1. **build 前守門**：`df --output=avail -k /` 檢查，可用 < **6G** 就**中止**（快速失敗，勿吃爆磁碟）。
2. **push 成功後立即清理**：`docker image prune -a -f && docker builder prune -f`
   （builder stage、base pull、最終映像全清 → 回到 baseline）。
3. **push 失敗也清理**：trap 保證失敗路徑同樣 prune，不累積殘層。
4. **不預拉 base、不設 sccache**（BuildKit cache mount 見下「編譯 cache」，待拍板）。
5. 常駐總佔用（系統 2.6G + runner ~0.2G）≈ 2.8G，**長期待機剩 ~7.2G**，安全（部署後實測剩 7.5G）。

### 編譯 cache（已定案 Tier 2，2026-09-18）
BuildKit（docker 29 預設）下用 cache mount 把 cargo 狀態提到 host 持久區（`redlib/Dockerfile` 已改）：
- **registry cache**：`--mount=type=cache,id=redlib-cargo-registry,target=/root/.cargo` 包住 `cargo fetch`
  （免重複下載 ~450 crates；常駐 ~0.5G）。
- **target cache**：`cargo build` 再加 `--mount=type=cache,id=redlib-cargo-target,target=/cache/target`
  + `--target-dir /cache/target`（**增量編譯**：改 merge 鏈重 build 只重編受影響 crate，秒~1 分；
  常駐 ~2.5-3.5G）。
- **關鍵陷阱**：cache mount 的內容**不屬於** stage 映像——所以 build 後必須
  `cp /cache/target/.../redlib dist/redlib`，release stage 改 `COPY --from=builder /redlib/dist/redlib`。
- 紀律（已落地到 workflow）：build 前 `disk_guard.sh`（可用 < **2.5G** 即中止，Tier 2 常駐 cache 下門檻）；
  build step 用 `trap 'docker image prune -a -f' EXIT` 保證成功/失敗都清 layer；
  **絕不跑 `docker builder prune`**（會刪 cargo cache）；以 `docker builder du` 監控，
  超預算時一次性 `docker builder prune -af` 回收。
- 另注意：`git clone` 層被 docker 層 cache 住時**不會**抓上游 redlib main 的新 commit（要 `--no-cache` 或 cache-bust ARG）；
  對測試自己的 PR bake 反而是優點（決定論）。

### RAM 注意
10G RAM 無 swap；cargo 5 並行 release build 峰值約 3-5G，可行。同機若日後加高負載服務，重估。

## 「只上傳 Codeberg，本地不放產物」——可行且即現行設計
- 本地 Forgejo 只當 **git host + CI 調度**，它的 container registry（packages 功能）**完全不使用**，
  任何編譯產物都不會落在那裡。
- Runner 在 12 上 build 完，**直接 `docker push codeberg.org/Lawlietr/redlib:latest`**，
  push 完即 prune——12 上也只剩 runner 本身的映像。
- 即：**產物只存在 codeberg.org**；12 只有「build 期間的瞬時占用」，Forgejo 端零占用。

## 註冊（已完成，機敏）
- 已於本地 Forgejo redlib_docker（repo 層級）建立 runner；UUID + Token 在 12 的
  `config/config.yaml`（uuid）與 `credentials/token.txt`（token，`token_url` 引入）。
- **勿寫入版本庫。** 舊機制（`register` 命令流程）的 token 已棄用，勿再用。
- `CODEBERG_PAT`（write:packages）設於本地 Forgejo 的 redlib_docker repo secrets（**尚未設，首次 build 前必須完成**）。

## Workflow 修正（已改待推送）
`.forgejo/workflows/build.yml` + `.forgejo/scripts/`：`runs-on: redlib`、podman→docker、
登錄區 `codeberg.org/Lawlietr/redlib:latest`、`disk_guard.sh` 守門、trap prune（見上紀律）。
觸發：push 到 main 且 `*/Dockerfile` 有變、或手動 dispatch。

## 遷移
- **Forgejo 端零改動**：註冊資訊（uuid/token）在 runner 側（`/opt/forgejo-runner/`），
  遷移 = 搬整個目錄到新機器（新機器需 docker + 可達 124:3000 + 磁碟 ≥10G）。
- 舊新兩台同時 online 且 label 相同會重復接單 → 新機上線後停舊機，必要時在 UI 刪舊 runner 紀錄（清單，非設定）。

## 部署後驗證
1. Forgejo UI 的 runner 名單 online。
2. 手動觸發 workflow → checkout → 磁碟守門通過 → docker build → push → prune。
3. `codeberg.org/Lawlietr/redlib:latest` 在 Codeberg package 頁面可見；
   事後 `df -h /` 與部署前持平（±0.1G 以內）。

## 機敏資訊處理（切記）
- uuid/token/`CODEBERG_PAT` 只放 12 的 `/opt/forgejo-runner/` 與 Forgejo secrets，**不進 git**；版本庫一律占位符。

## 參考
- Forgejo Runner 安裝/註冊/設定（v15）：`https://forgejo.org/docs/v15.0/admin/actions/`
- 標籤：`<name>:<type>://<image>`；host 型為 `<name>:host`（step 跑在 runner 自身）。
