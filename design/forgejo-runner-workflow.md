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
