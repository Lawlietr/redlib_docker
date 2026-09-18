# Forgejo Runner Docker 部署 — 實施要領（12 機，10GB 磁碟）

> 2026-09-18 定案：Runner 以 **Docker 形式**部署在 **192.168.1.12（Ubox-02）**（純 docker host，
> 無 komodo）。**12 只有 10GB 磁碟，磁碟紀律是本方案核心。** 對 12 的評估全程唯讀。
> 產出的映像**只推送至 Codeberg 登錄區**（`codeberg.org`），本地 Forgejo 與 12 都不保留編譯產物（見下）。

## 目標
12 上的 Forgejo Runner 執行 `.forgejo/workflows/build.yml`：docker build redlib → 推送 `codeberg.org/Lawlietr/redlib:latest` → **本地清理**。

## 已查證環境（12，唯讀）
- Ubox-02，Ubuntu 24.04.5，x86_64，**5C / 10G RAM**（可用 ~9.9G）。
- **磁碟 10GB（zfs subvol），已用 2.6G、剩 7.5G**。
- Docker 29.8.1，**完全乾淨：0 映像、0 容器**。無 podman/cargo/node（只有 docker + git）。
- outbound 可達：docker.io、data.forgejo.org、codeberg.org；到 Forgejo `http://192.168.1.124:3000` 13ms。
- 無 komodo（124 的 komodo 管理不涵蓋 12）→ 用**單機 compose 目錄**管理。
- runner 鏡像源：`data.forgejo.org/forgejo/runner`，最高 `13.1.0`（runner 版本獨立於 Forgejo；Forgejo 15 文件示範即 `:13`）。

## 部署：單機 compose 目錄
目錄：`/opt/forgejo-runner/`（12 上）
- `compose.yaml`：單一 runner 容器。
- `runner-config`：server `url: http://192.168.1.124:3000` + uuid/token（**機敏，留在 12，不進 git**）。
- `data/`：runner 狀態 + job workspace（job 只 checkout 本 repo，很小；docker build 產物在 docker 層，不在此）。
- runner 鏡像：由 `data.forgejo.org/forgejo/runner:13.1.0` **擴建**（`Dockerfile` 同目錄，`docker build` 一次）：
  補 **nodejs（actions）+ git + docker-cli + ca-certificates**。base 應為 alpine（`apk`），部署時先確認。
  **不需 rust/cargo**——redlib 的 cargo build 在 `redlib/Dockerfile` builder stage 容器內。
- label：`redlib:host`（host label 的 step 跑在 runner 容器自身 → 工具鏈裝在鏡像裡）。
- volumes：設定檔（ro）、`/var/run/docker.sock`（docker build/push 直用 host daemon，免 DinD）、`./data`。
- `restart: unless-stopped`。
- 註冊：官方 runner 需先 `register` 後 `daemon`；以 entrypoint `forgejo-runner register && forgejo-runner daemon` 完成（uuid/token 在設定檔）。

## 磁碟紀律（10GB，核心）
### 預算
| 項目 | 大小 | 性質 |
|---|---|---|
| 既有系統 | 2.6G | 常駐 |
| runner 擴建映像（runner+node+git+docker-cli） | ~0.4G | 常駐 |
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
4. **不設持久 cache**：不預拉 base、不設 BuildKit cache mount、不設 sccache——每次 build 從零，
   換取磁碟可預測（代價：每次 build 慢一些，接受）。
5. 常駐總佔用（系統 2.6G + runner ~0.5G）≈ 3.1G，**長期待機剩 ~6.9G**，安全。

### RAM 注意
10G RAM 無 swap；cargo 5 並行 release build 峰值約 3-5G，可行。同機若日後加高負載服務，重估。

## 「只上傳 Codeberg，本地不放產物」——可行且即現行設計
- 本地 Forgejo 只當 **git host + CI 調度**，它的 container registry（packages 功能）**完全不使用**，
  任何編譯產物都不會落在那裡。
- Runner 在 12 上 build 完，**直接 `docker push codeberg.org/Lawlietr/redlib:latest`**，
  push 完即 prune——12 上也只剩 runner 本身的映像。
- 即：**產物只存在 codeberg.org**；12 只有「build 期間的瞬時占用」，Forgejo 端零占用。

## 註冊（人工、機敏）
- 本地 Forgejo → redlib_docker → Settings → Actions → Runners → Create new runner（repo 層級）。
- UUID + Token 填入 12 的 runner-config（**勿寫入版本庫**）。
- `CODEBERG_PAT`（write:packages）設於本地 Forgejo 的 redlib_docker repo secrets。

## Workflow 同步修正（部署時一起做）
見 `forgejo-runner-workflow.md`：`runs-on: redlib`、podman→docker、登錄區 `codeberg.org/Lawlietr/redlib:latest`；
另加**磁碟守門**與 **push 後 prune** 步驟（紀律 1-3）。

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
