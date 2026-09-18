# TODO

本文件**只**記錄工作進度與優先級。實作細節（步驟、設定、注意事項）見 `design/` 目錄，不贅於此。

## 優先級定義
- **P0** 阻斷 —— 擋住其他工作的東西
- **P1** 高 —— 應儘速處理
- **P2** 中 —— 排程進行
- **P3** 低 —— 順便處理

---

## P1 待辦

- [ ] **接線 redlib build workflow 並完成首次 build**
  - 狀態：runner 已上線（label `redlib`）；cbgproxy workaround + socket 權限（`--group-add 990`）+ login 重試已就緒；推送即觸發 build。
  - 前置（唯一阻斷）：`CODEBERG_PAT`（write:packages）設於本地 Forgejo 的 redlib_docker repo secrets（**尚未確認；沒設的話 login 重試 6 次後仍會失敗**）。
  - 已定案：cargo cache **Tier 2**（registry + target cache mount，增量編譯）。
  - 實作要領：`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`。

## P2 待辦

- （目前無）

## 已完成

- [x] 部署 Forgejo Runner（Docker 形式，12 機 192.168.1.12，`/opt/forgejo-runner/` 單機 compose，label `redlib:host`，2026-09-18 上線）；產物只推 `codeberg.org`，本地 Forgejo/12 不保留
- [x] 12 機 cbgproxy 反向代理 workaround（codeberg 邊緣砍連線；含 token curl 攔截 + 重試）＋ runner 容器 docker socket 權限修正（`--group-add 990`）；要領見 `design/forgejo-runner-workflow.md` §6
- [x] 新增 Codeberg Forgejo Actions workflow（`.forgejo/workflows/build.yml`，podman / amd64 / 推 `registry.codeberg.org`）
- [x] Dockerfile bake PR #506 #509 #521 #560 #539 #549（`--depth 300` + `-X ours` merge 鏈）
- [x] 於 `AGENTS.md` 記錄 PR bake 清單與 merge 機制
- [x] 新增 MIT `LICENSE`（repo 自有檔 MIT；上游 redlib 保留 AGPL-3.0）
- [x] commit 並推送至 `origin` 與 `codeberg` 兩個 remote
