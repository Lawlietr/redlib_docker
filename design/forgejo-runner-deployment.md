# Forgejo Runner Docker 部署 — 實施要領（komodo stack，124 機）

> 2026-09-18 定案：Runner 以 **Docker 形式**部署在 **192.168.1.124（ubuntu-01）**，
> 用 **komodo** 管理（獨立 stack）。本文件為**唯讀評估後的實施計畫**；124 上未做任何改動。
> Forgejo 為線上重要服務——**不得修改其設定或重啟**，本方案不觸及 `124_forgejo` stack。

## 目標
架設本機 Forgejo Runner（Docker），讓本地 Forgejo 執行 `.forgejo/workflows/build.yml`，
建構 redlib 映像並推送至 Codeberg 登錄區（`codeberg.org`）。

## 已查證環境（124，唯讀）
- ubuntu-01，8C / 10G RAM（評估時可用 ~7.5G），Docker 29.8.1。
- 在跑容器：`forgejo-1`（`codeberg.org/forgejo/forgejo:15`，3000/222）、palworld、beszel-agent、
  `komodo-periphery-periphery-1`、`watchtower_124`。
- **124 無** rust/cargo/node/podman（只有 docker + git）。
- komodo = moghtech/komodo-periphery（Web UI :8120，根目錄 `/etc/komodo`），124 上**無 komodo CLI**。
  管理方式：`/etc/komodo/stacks/<124>_<name>/` 一目錄 = `compose.yaml` + data 目錄，經 periphery UI 管理。
- 現有 stack：`124_7daystodie`、`124_forgejo`、`124_libretranslate`、`124_palworld-server`、`124_watchtower`。
- `124_forgejo/compose.yaml` 很簡潔（image + `./forgejo` data + ports 3000/222 + 私有 network），
  敏感設定不在 compose 檔內。
- Runner 鏡像：`data.forgejo.org/forgejo/runner`（124 可達）。**runner 版本獨立於 Forgejo 版本**，
  目前最高 `13.1.0`（Forgejo 15 官方文件示範即用 `runner:13`）。→ 用 `data.forgejo.org/forgejo/runner:13.1.0`。

## 部署方式：獨立 komodo stack（不動現有 forgejo stack）
新增目錄：`/etc/komodo/stacks/124_forgejo-runner/`
- `compose.yaml` —— runner 容器。
- `runner-config`（設定檔，含 server url + uuid/token；**機敏，留在 124，不進 git**）。
- `data/` —— runner 狀態/快取（volume）。

runner 容器要點：
- image：由 `data.forgejo.org/forgejo/runner:13.1.0` **擴建**一個小鏡像（同機 docker build 一次）：
  補 `nodejs`（actions 用）、`git`、`docker-cli`、`ca-certificates`。
  **不需 rust/cargo**——redlib 的 cargo build 發生在 `redlib/Dockerfile` 的 builder stage（Docker build 內部）。
- server url：`http://192.168.1.124:3000`（或 `host.docker.internal`；不接 forgejo 私有 network，走 LAN 位址最簡單）。
- volumes：
  - runner 設定檔（ro）
  - `/var/run/docker.sock` —— workflow 的 `docker login/build/push` 直用 host daemon（免 DinD）
  - `./data` —— runner 狀態
- label：`redlib:host`（host label 的 step 在「fork 自 runner 的 shell」裡跑，
  即 runner 容器內部 → 所以工具鏈要裝在 runner 鏡像裡，見上）。
- `restart: unless-stopped`；`container_name: forgejo-runner_124`（沿用 `*_124` 命名慣例）。
- 註冊：官方 runner 需先 `register` 後 `daemon`；Docker 形式通常以 entrypoint
  `forgejo-runner register && forgejo-runner daemon` 一次完成（uuid/token 在設定檔內）。

## 註冊（人工、機敏）
- 本地 Forgejo → redlib_docker → Settings → Actions → Runners → Create new runner（repo 層級）。
- 取得 UUID + Token，填入 124 上的 runner 設定檔（**勿寫入版本庫**）。
- `CODEBERG_PAT`（write:packages）設於本地 Forgejo 的 redlib_docker repo secrets。

## Workflow 同步修正（部署時一起做）
見 `forgejo-runner-workflow.md`：`runs-on: redlib`、podman→docker、登錄區 `codeberg.org/Lawlietr/redlib:latest`。

## 遷移（回答「遷移要不要改 Forgejo 設定？」）
**不需要改 Forgejo 的設定。**
- 註冊資訊（uuid/token）存在 **runner 側**（stack 目錄裡的設定檔），不在 Forgejo 設定裡。
  Forgejo 端只有一個「已註冊 runner」的名單紀錄（名稱/說明，資訊性）。
- 遷移 = 把 `124_forgejo-runner/` 整個 stack 目錄（compose + 設定 + data）搬到新機器 → 起容器 →
  同一支 runner（同 uuid）上線。**Forgejo 端零改動**。
- 唯一可能調整：新機器若以不同路徑連 Forgejo，改 runner 設定檔的 `url` 即可。
- 注意：遷移期間若**舊新兩台 runner 同時 online 且 label 相同**，job 可能被兩台各接一次 →
  新機上線確認後，停掉舊機容器；必要時在 Forgejo UI 的 runner 名單刪舊紀錄（這是清單，非設定）。
- komodo stack = 「一個目錄」，正是為了這種可搬遷性：搬目錄即可。

## 資源風險
- 124 可用 ~7.5G RAM；redlib cargo build 在 builder 容器內，吃 CPU/RAM 較重（同機還有 palworld）。
  可行但偏緊，首次 build 建議觀察；若壓力大，可將 runner stack 遷到資源較多的機器（遷移方式見上，Forgejo 端不用動）。

## 部署後驗證
1. Forgejo UI 的 runner 名單顯示 online。
2. 手動觸發 workflow（workflow_dispatch），job 排到 `redlib` 並跑通 checkout → docker build → push。
3. `codeberg.org/Lawlietr/redlib:latest` 在 Codeberg 的 package 頁面可見。

## 機敏資訊處理（切記）
- uuid/token/`CODEBERG_PAT` 只放 124 的 stack 目錄與 Forgejo secrets，**不進 git**。
- 版本庫內一律占位符（`<UUID>`/`<TOKEN>`/`<PAT>`）。

## 參考
- Forgejo Runner 安裝/註冊/設定（v15）：`https://forgejo.org/docs/v15.0/admin/actions/`
- 標籤格式：`<label-name>:<label-type>://<default-image>`（host 型為 `<name>:host`，step 跑在 runner 自身）。
