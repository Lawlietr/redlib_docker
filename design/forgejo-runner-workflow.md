# Workflow 調整 — 登錄區網址、runs-on、建構工具

## 背景
現行 `.forgejo/workflows/build.yml` 為 Codeberg 託管 runner（podman / `codeberg-medium` /
`registry.codeberg.org`）設計，與本機自架 Runner 不符。部署時需一併修正以下三點（外加認證）。

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
- 本機：有 docker、無 podman → 改用 **docker**（`docker login` / `docker build` / `docker push`）。
- docker build/push 直接連本機 daemon，不需 DinD。

## 4. 認證
- `docker login codeberg.org -u <user> -p <PAT>`。
- PAT 需 **write:packages** 範圍；Runner 自動生成的 token **推不上**登錄區。
- secret 名稱：`CODEBERG_PAT`，設於**本地 Forgejo** 的 redlib_docker repo secrets（workflow 在本地 Forgejo 執行）。
- **機敏，勿寫入版本庫。**

## 推送目標
- `codeberg.org/Lawlietr/redlib:latest`（tag 視需要調整）。
- 注意：此處推至 **public codeberg.org** 登錄區。
- 若日後要改推至「本地 Forgejo 自身的登錄區」，網址與認證不同，需另行處理（不在此流程內）。

## 與 `.github/workflows/build.yml` 的關係
- `.github/` 那份是 GitHub ghcr.io 的 guarded 備援（`if: github.server_url == 'https://github.com'`），
  推到 `ghcr.io`，**不用動**。
- 只有 `.forgejo/workflows/build.yml` 需要上面四項修正。
