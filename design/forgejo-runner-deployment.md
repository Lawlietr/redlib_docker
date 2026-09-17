# Forgejo Runner 本機部署 — 實施要領

## 目標
架設一台本機 Forgejo Runner，讓 **本地 Forgejo**（Forgejo Actions）能執行 `.forgejo/workflows/build.yml`，
建構 redlib 容器映像並推送至 Codeberg 登錄區。

## 背景：Forgejo 沒有託管 runner
Forgejo（含 Codeberg）不像 GitHub 有 hosted runner。Actions 只讀 workflow，
實際工作由**你自己架設的 Forgejo Runner** 執行。所以本任務是「架 runner」而非「開啟 Actions」。

## 已查證拓撲
- **Runner 主機**：`192.168.1.15`（本 agent 主機）。
  - 已裝：docker 29.7.2、rust/cargo 1.98、node 22、git。
  - 未裝：podman。
- **Forgejo 主機**：`192.168.1.124`（host 名 `fg` / `forgejo`），v15.0.8，Docker 部署。
- **連線**：Runner 連 `http://fg:3000`。

## 標籤選型：用 `host`（免 DinD）
- 本機已有 docker/rust/node/git，`host` label 讓 job 直接在本機原生執行。
- `docker build/push` 直接用本機 daemon，**不需 DinD、不需掛 docker socket**。
- 代價：job 以 root 在本機執行、完全無隔離。本機開發用途可接受。
- Runner label：`redlib:host`  →  workflow `runs-on: redlib`。
- （若日後要隔離，可改用 `docker` label + DinD，但複雜度高很多，本機環境不建議。）

## 安裝方式（二選一）
### 選項 A：官方 binary + systemd（推薦，host label 最穩）
1. 下載 **Forgejo Runner v15** 的 runner binary（版本需與 Forgejo 15 相容）。
2. 產生設定檔：`generate-config`（官方 CLI 指令）。
3. 編輯設定檔：
   - `server.connections.forgejo`：`url` = `http://fg:3000`、`uuid`、`token`（來自 UI，機敏）。
   - `runner.labels`：`- redlib:host`。
4. 註冊：`register`（使用 uuid + token）。
5. 以 systemd service 執行：`daemon`。
- 官方 CLI 指令與設定格式以官方 installation 文件為準。

### 選項 B：Docker 執行
- 官方鏡像 `data.forgejo.org/forgejo/runner:15`，或社群 `davbfr/forgejo-runner`（可用環境變數設定）。
- 用 `host` label 時，runner 需在容器內 fork 本機行程，穩定度不如 binary。
- 本機環境優先選 A；B 僅作「全 Docker 化」的替代。

## 註冊（人工、機敏）
- 登入本地 Forgejo → redlib_docker → **Settings → Actions → Runners** → **Create new runner**。
  - 選 **repo 層級**（`/{owner}/{repository}/settings/actions/runners`）則只有 redlib_docker 會用這台 runner。
  - 也可選 user / org / system 層級（範圍更大）。
- 取得 **UUID + Token**（**機敏資訊，勿寫入版本庫**）。

## 機敏資訊處理（切記）
- `uuid` / `token` / `CODEBERG_PAT` 皆屬機敏。
- **只放在伺服器本機設定檔或 Forgejo secrets，不進 git。**
- 設定檔範例中的 uuid/token 用占位符（`<UUID>` / `<TOKEN>`），實際值手填。
- 建議對設定檔/啟動腳本加 `.gitignore` 或確保不在版本庫。

## 部署後驗證
1. Runner 在 Forgejo UI 顯示 **online**。
2. 觸發一次 build，job 排到 `redlib` label 並跑通。
3. 映像成功推送至登錄區。

## 參考
- Forgejo Runner 安裝/註冊/設定（v15）：`https://forgejo.org/docs/v15.0/admin/actions/`
- 標籤格式：`<label-name>:<label-type>://<default-image>`（type = docker | lxc | host）。
