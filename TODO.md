# TODO

本文件**只**記錄工作進度與優先級。實作細節（步驟、設定、注意事項）見 `design/` 目錄，不贅於此。

## 優先級定義
- **P0** 阻斷 —— 擋住其他工作的東西
- **P1** 高 —— 應儘速處理
- **P2** 中 —— 排程進行
- **P3** 低 —— 順便處理

---

## P1 待辦

- （目前無）

## P2 待辦

- （目前無）

## 已完成

- [x] 接線 redlib build workflow 並完成首次 build（2026-09-18：CI 首次完整 build+push 到 `codeberg.org/lawlietr/redlib:latest` 成功，映像公開可匿名 pull；runner 12 機、docker+BuildKit、cargo cache Tier 2）
- [x] 部署 Forgejo Runner（Docker 形式，12 機 192.168.1.12，`/opt/forgejo-runner/` 單機 compose，label `redlib:host`，2026-09-18 上線）；產物只推 `codeberg.org`，本地 Forgejo/12 不保留
- [x] 12 機 cbgproxy 反向代理 workaround（codeberg 邊緣砍連線；含 token curl 攔截 + 重試）＋ runner 容器 docker socket 權限修正（`--group-add 990`）；要領見 `design/forgejo-runner-workflow.md` §6
- [x] Forgejo Actions workflow（`.forgejo/workflows/build.yml`，docker / amd64 / 推 `codeberg.org/lawlietr/redlib`；GitHub ghcr workflow 保留為 guarded backup，只在 github.com 上觸發）
- [x] Dockerfile bake PR #506 #509 #521 #560 #539 #549（`--depth 300` + `-X ours` merge 鏈）→ 2026-09-18 退役：#506/#521/#560/#539/#549 已全部并入 upstream main（至 `8167e00`），#509 被 wreq 遷移取代；Dockerfile 改回 `--depth 1` 直接 build main
- [x] 於 `AGENTS.md` 記錄 PR bake 清單與 merge 機制（現已更新為退役狀態）
- [x] 新增 MIT `LICENSE`（repo 自有檔 MIT；上游 redlib 保留 AGPL-3.0）
- [x] README 重寫（拉預編譯映像 + `docker` / `docker-compose` 部署；映像參考統一小寫 `lawlietr`）；移除過期 `REDIS_URL` 描述（現行 redlib 無 Redis 支援）
- [x] 建置檔移到根目錄（廢除 `redlib/` 子目錄與 multi-app 偵測機制；單 app 專屬，觸發路徑改 `Dockerfile`，映像名固定 `redlib`）
- [x] commit 並推送至 `origin` 與 `codeberg` 兩個 remote
