# TODO

本文件**只**記錄工作進度與優先級。實作細節（步驟、設定、注意事項）見 `design/` 目錄，不贅於此。

## 優先級定義
- **P0** 阻斷 —— 擋住其他工作的東西
- **P1** 高 —— 應儘速處理
- **P2** 中 —— 排程進行
- **P3** 低 —— 順便處理

---

## P1 待辦

- [ ] **部署本機 Forgejo Runner**（讓本地 Forgejo 能建構並推送 redlib 映像）
  - 狀態：規劃已完成，**等待註冊 token 方可執行**。
  - 阻斷因素：需從本地 Forgejo UI 取得 Runner 註冊 **UUID + Token**（機敏，勿寫入版本庫）。
  - 前置：確認 `CODEBERG_PAT`（write:packages）已設於本地 Forgejo 的 redlib_docker repo secrets。
  - 部署時需同時修正 `.forgejo/workflows/build.yml`：登錄區 `registry.codeberg.org` → `codeberg.org`、`runs-on` → 自架 label、podman → docker（本機無 podman）。
  - 實作要領：`design/forgejo-runner-deployment.md`、`design/forgejo-runner-workflow.md`。

## P2 待辦

- （目前無）

## 已完成

- [x] 新增 Codeberg Forgejo Actions workflow（`.forgejo/workflows/build.yml`，podman / amd64 / 推 `registry.codeberg.org`）
- [x] Dockerfile bake PR #506 #509 #521 #560 #539 #549（`--depth 300` + `-X ours` merge 鏈）
- [x] 於 `AGENTS.md` 記錄 PR bake 清單與 merge 機制
- [x] 新增 MIT `LICENSE`（repo 自有檔 MIT；上游 redlib 保留 AGPL-3.0）
- [x] commit 並推送至 `origin` 與 `codeberg` 兩個 remote
