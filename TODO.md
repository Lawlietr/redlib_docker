# TODO

本文件**只**記錄工作進度與優先級。實作細節（步驟、設定、注意事項）見 `design/` 目錄，不贅於此。

## 優先級定義
- **P0** 阻斷 —— 擋住其他工作的東西
- **P1** 高 —— 應儘速處理
- **P2** 中 —— 排程進行
- **P3** 低 —— 順便處理

## 維護規則
- 本檔是「活板」：待辦（P0–P3）永遠在頂部；已完成只放在下方「近期完成」。
- 「近期完成」保留最近 **10 筆**；超過的剪掉。已完成工作的完整記錄在 `git history` 與 `design/` 裡，不需在此重複貼。
- 每次工作結束時 prune 一次。

---

## P0 待辦

- [ ] **多平台建置（amd64 + arm64，Plan B）**：核心原則**編譯在 12 runner（Ubox-02）跑，push 到 `codeberg.org/lawlietr/redlib`**。musl 靜態、原生交叉編譯（無 QEMU）、sequential build/push/prune、`latest` + `<git-sha>` manifest list。**僅 amd64 + arm64**（armv7 已移除）。進度：(1) ✅ `build_and_push.sh` 已補 `CXX_*`/`AR_*`（commit `fc555ee`）；(2) ⏳ runner（Alpine）需擴建：`apk add` cross-compiler + clang + rustup/cargo；(3) ⏳ 重建 runner → 觸發 workflow 實跑兩平台；(4) ⏳ codeberg manifest 實測驗證。實作細節見 `design/multi-arch-build.md`。

## P1 待辦

- （目前無）

## P2 待辦

- [ ] GitHub Actions 建置流程（**中高優先**）：目前 forgejo/codeberg runner 已能編譯並推送映像；下一步把相同的 build + push 能力做到 GitHub Actions（推送 `ghcr.io`）。**workflow 已寫好（`.github/workflows/build.yml` + `.github/scripts/build_and_push.sh`），待加入 GitHub 遠端後即可跑**。實作細節見 `design/github-actions-workflow.md`。

## P3 待辦

- [ ] GitHub Actions 兩平台（multi-arch）同步：待 P0 多平台定案且有 GitHub repo 後，把 amd64/arm64 的 build+push 同步到 `ghcr.io`（與 `.forgejo` 兩平台流程對稱）。這與 P2（把現行單 arch 流程 mirror 到 ghcr.io，workflow 已寫好）是**不同項目**。實作細節見 `design/multi-arch-build.md` §11。

---

## 近期完成（保留最近 10 筆）

- [x] 12 機磁碟擴至 30GB（原 10GB，2026-09-18）：設計檔、`disk_guard.sh`（守門 2.5G→6G）、`build.yml`、AGENTS.md 已全部更新；多架構一次編也绰有餘裕，仍保留逐檔 prune 習慣
- [x] 接線 redlib build workflow 並完成首次 build（2026-09-18：CI 首次完整 build+push 到 `codeberg.org/lawlietr/redlib:latest` 成功，映像公開可匿名 pull；runner 12 機、docker+BuildKit、cargo cache Tier 2）
- [x] 部署 Forgejo Runner（Docker 形式，12 機 192.168.1.12，`/opt/forgejo-runner/` 單機 compose，label `redlib:host`，2026-09-18 上線）；產物只推 `codeberg.org`，本地 Forgejo/12 不保留
- [x] 12 機 cbgproxy 反向代理 workaround（codeberg 邊緣砍連線；含 token curl 攔截 + 重試）＋ runner 容器 docker socket 權限修正（`--group-add 990`）；要領見 `design/forgejo-runner-workflow.md` §6
- [x] Forgejo Actions workflow（`.forgejo/workflows/build.yml`，docker / amd64 / 推 `codeberg.org/lawlietr/redlib`；GitHub ghcr workflow 保留為 guarded backup，只在 github.com 上觸發）
- [x] Dockerfile bake PR #506 #509 #521 #560 #539 #549（`--depth 300` + `-X ours` merge 鏈）→ 2026-09-18 退役：#506/#521/#560/#539/#549 已全部并入 upstream main（至 `8167e00`），#509 被 wreq 遷移取代；Dockerfile 改回 `--depth 1` 直接 build main
- [x] 於 `AGENTS.md` 記錄 PR bake 清單與 merge 機制（現已更新為退役狀態）
- [x] 新增 MIT `LICENSE`（repo 自有檔 MIT；上游 redlib 保留 AGPL-3.0）
- [x] README 重寫（拉預編譯映像 + `docker` / `docker-compose` 部署；映像參考統一小寫 `lawlietr`）；移除過期 `REDIS_URL` 描述（現行 redlib 無 Redis 支援）
- [x] 建置檔移到根目錄（廢除 `redlib/` 子目錄與 multi-app 偵測機制；單 app 專屬，觸發路徑改 `Dockerfile`，映像名固定 `redlib`）
