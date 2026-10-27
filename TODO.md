# TODO

> 本檔只放**工作進度與優先級**。每個項目 = 做什麼 + 為什麼/範圍 + 優先級，並連結到 `design/` 的實作指引。
> 詳細說明、踩坑、部署步驟一律放 `design/`，不在這裡重複。
> 本專案的 CI：本地 Forgejo（多架構發佈）+ GitHub Actions（amd64 編譯、ghcr 鏡像）。

## 優先級定義

| 級 | 含義 |
|----|------|
| **P0** | 緊急且重要：阻塞部署/上線、影響正確性或穩定性，需立即處理 |
| **P1** | 重要不緊急：影響可靠性/可觀測性/品質，近期要推但非阻塞 |
| **P2** | 有價值但可排後：改善體驗、重構、非阻塞的補齊 |
| **P3** | 想法/可選：nice-to-have、長期評估項 |

## 維護慣例
- **commit 訊息一律用英文**（conventional-commit 風格的 subject，body 也用英文）。文件照雙語慣例：README 繁中/英文、`RELEASE_NOTES.md` 英文、`design/` 繁中。
- 完成項移到「近期完成」並標日期；**待辦一律放上方對應優先級**，不要只寫在「近期完成」的敘述裡。
- 新增待辦時直接開新條目（優先級由你指定或先問）。
- 每條待辦保持「做什麼 + 為什麼/範圍 + 優先級 + design 連結」四要素，細節不展開。

## P2 — 正式實例的更新路徑沒有蓋到 redlib（「同一 digest」假象的根源）
- **做什麼**：把兩台正式實例的 redlib 更新機制補齊並寫成 design 檔：amd64 那台的 watchtower 清單沒有 redlib（等於不會自動更新），另一台雖在清單內但每 6 小時才掃一次；兩台的 stack 都由 Komodo 管。決定要用 watchtower、Komodo 的自動部署，還是明確標成「手動拉取」，並附上可複製的更新步驟（第一步永遠是確認執行中的 image id）。
- **為什麼**：這次排障差點被誤判成「同一支映像兩台行為不同」，實際原因是**兩台都還在跑 4 天前的舊 pin**（新版本已發佈但沒人被拉）。更新路徑不明 → 以後每次比較實例都要先花時間證明版本一致，也代表修正與安全更新有隱性延遲。
- **優先級**：P2（不阻塞使用，但直接影響排障成本與 patched 上線時效）。
- **參考**：`design/error-triage-playbook.md` §4.2 的「步驟 0」（指令與這次的實測數據）。

## P2 — 裸 IP 公開的 redlib 與「假 TW-only」（兩個暴露面）
- **做什麼**：(1) 把 `http://o1PublicIP:8084/`（o1）與 `http://o3PublicIP:8084/`（o3）從「任何人用裸 IP 就能用」收回去：改成只綁 ZeroTier/LAN，或把 o1 那台（舊 pin、貼文頁全壞的幽靈實例）直接停掉；順帶清掉 Zoraxy `ddit` 規則裡的 `InactiveOrigins`（已死的 `10.0.0.134:8084`、`o1ZT:8084`、`o1ZT:8095`）。**(2) 2026-10-27 已部分處理**：`Enable Trusted Proxy Gating` 已開（`b6f4dd52` 與 `ZoraxyFilterID` 兩條 filter 現在都是 `TrustProxyHeadersOnly: true`），並把白名單 `Taiwan White`（`b6f4dd52`）掛到 `ddit`；複驗：TW 出口 200、JP 出口（o3 公網）403、裸 IP 進入 403。**殘留兩項**：(a) `WhitelistAllowLocalAndLoopback=false` 且 `10.147.17.0/24` 不在白名單 → **ZeroTier／LAN／loopback 現在進不去 ddit，break-glass 消失**，要加 CIDR 或開 LAN/Loopback；(b) JP 出口的監控（Uptime Kuma／Beszel）對 ddit 會開始回報 403，要嘛白名單其出口 IP，要嘛讓監控直打 `123:8080`。原本掛在 ddit 的黑名單 `ZoraxyFilterID-…`（`RU CN MX Blacked`）其實是 `BlacklistEnabled=true` / `WhitelistEnabled=false` 的黑名單，以前 gating 沒開時從 JP 出口打得進 200 → 若要真正的 TW-only，**先**在那條 filter 上打開 **Enable Trusted Proxy Gating**（否則 Zoraxy 拿 CF 邊緣节點的國家去判，白名單會連你自己都 403），再留 `tw` +self 的 IP 白名單；或改在 nx 用 `CF-IPCountry` 實作。同一個坑的實測對照表與 Zoraxy 原始碼引用見 `design/reverse-proxy-front.md` §3.3；掛了 `Taiwan White` 的 `note.avpclub.uk` **目前就是壞的狀態**（透過 CF 一律 403，只有繞過 CF 直連 o3 才 200）。另：`conf/log_conf.json` 是 `enabled:false`，access log 全空，排障前要先在 UI 打開。
- **為什麼**：裸 IP 的 HTTP 端點等於多兩台不受域名過濾的實例（其中一台還是舊 pin、全壞），而且「Taiwan Only」這個描述現在**不成立**——任何非 CN/MX/RU 的訪客都進得來，這與我們以為的政策相反。
- **優先級**：P2（正式服務沒壞，但政策與暴面和認知不一致；處理前會碰到入口層，需在場確認）。
- **參考**：`design/reverse-proxy-front.md` §3（實測與檔位）、§4（nx 上的 TW-only 寫法）。

## P3 —（選用）把前門從 o3 搬到 nx 的 nginx：可用但非必要，附完整配方與代價
- **做什麼**：現階段**不做**。要做時照 `design/reverse-proxy-front.md` §4：DNS 只改一行（`ddit` CNAME `o3.avpclub.uk` → `hm.avpclub.uk`，保持 proxied），nx 新增 vhost（通配證已在 `/etc/nginx/ssl/*.avpclub.uk_avpclub.uk_EC256/`）`proxy_pass http://192.168.1.123:8080`，TW 過濾用 `CF-IPCountry`（nx 目前**沒有** `set_real_ip_from`/`real_ip_header`，且只有舊 GeoIP v1 db、沒有 GeoLite2 mmdb），並保留 o3 的 Zoraxy 規則當備援。
- **為什麼**：**搬前門不會改變 Reddit 看到的 IP**（出口仍是 123），ddit 現在就是好的（實測 200 / 150,701 B / 128 則）。搬的價值只有：自己控制過濾、少一跳 JP、不依賴 o3 當入口；代價是把 load 2.4–3.1、768MB RAM 的 2 vCPU 機體放進關鍵路徑。
- **優先級**：P3（觀望；只有在要嚴格 TW-only、或想把入口從雲上收回區網時才做）。
- **參考**：`design/reverse-proxy-front.md`（拓撲圖、§4 可直接貼的 nginx 設定、三條注意事項）。

## P3 — 上游 #603（GraphQL 留言）：目前不 bake，列為觀望，附三個觸發條件
- **做什麼**：不進 `redlib-prs.txt`；只在三個觸發條件任一成立時重啟評估（shreddit 路徑壞掉／我們需要突破每頁 200 則留言／上游把 #603 merge 進 main），並先讀出被封實例上那行完整錯誤再決定換手。
- **為什麼**：2026-10-27 已用三映像實測過——**拿掉 shreddit PR 後所有貼文頁在所有實例都拿不到留言**（代表現有方案是 load-bearing，不能因為它是 workaround 就丟）；#603 在出口可用的機器上可用且快 2.7–4×、並帶真正可用的分頁，但在被 Reddit 擋出口 IP 的那台上照樣 0 則留言，而且把依賴換成另一個未文件化的 Reddit 端點（Android persisted query）。
- **優先級**：P3（觀望；判定、數據與觸發條件都在 design）。
- **參考**：`design/upstream-pr-bake.md` §8.14（判定 + 觸發條件 + 尚未查明的點）、§7 的第二輪 A/B 表格。

## P2 — 鄰居故障：首頁與人機驗證（不在 #592 範圍）
- **做什麼**：另外單獨評估「首頁 feed 的 parse error」與「Anubis PoW 擋程式化存取」兩條上游 issue 對應的 PR。
- **為什麼**：貼文路由的修正明確標示不處理這兩條；若不另立條目會誤以為一併修好。
- **優先級**：P2（本機實測這兩個端點目前仍正常，先觀望）。
- 細節：`design/error-triage-playbook.md` §7 末段。

## P2 — 機房出口 IP 的實例：貼文頁全滅，且**不是 code 問題**
- **做什麼**：決定那個外網 VPS 實例的去處——三選一：(a) 把它的 redlib 搬到住宅出口的機器（內網那台已驗證可用）、(b) 替它做一條到住宅出口的 L3/L4 tunnel（兩台之間已有 ZeroTier 的痕跡可當候選）、(c) 接受它只有列表可用，貼文連結導到可用實例。
- **為什麼**：同一支映像（同一個 manifest digest）在內網機器上貼文頁正常、在外網 VPS 上每個貼文頁都失敗；差異只在**出口 IP 的信譽**（機房 ASN vs 住宅線）。這類故障**重產映像、換 env、重啟容器都無效**，掛 CDN 也不會救（CDN 只在進向），所以必須記成獨立條目，別再把它誤當 bake 問題重複調查。
- **狀態/優先級**：P2（一個對外實例的貼文頁不可用；已定因，尚未選擇處置）。
- 細節：`design/error-triage-playbook.md` §4.2（判別指令與對照表）、`design/upstream-pr-bake.md` §8.13（含 CDN 為何無關、以及 redlib 沒有出口代理設定這件事）。

## P1 — 上游未合併 PR 的 bake 鏈（Tier 1）
- **做什麼**：把 6 支仍未 upstream 合併的上游 PR（#549/#542/#521/#560/#539/#599）bake 進建置來源；清單放 `redlib-prs.txt`（單一來源），套用邏輯放 `.build/apply_redlib_prs.sh`，由 `Dockerfile` 與 `.forgejo/scripts/build_and_push.sh` 共用。
  > **已退役**：#592（貼文頁 403 繞行）於 2026-10-22 從 `redlib-prs.txt` 移除。上游 v0.40.0 以直接 commit `0a3e9cd` 實作等效 `%2f` 繞行（同碰 `src/client.rs`）；#592 作為 PR 從未合併，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故退役、thread-403 改由上游供應。見 `RELEASE_NOTES.md` 2026-10-22 段。
- **為什麼**：2026-09-18「已全部併入 upstream main」的判斷錯誤（引用的 commit 是我們 build 內的本地 merge tip），upstream main 至今沒有這些改動 → 現行發佈映像少了 CMAF/rich:video 影片、預設 post sort 生效、lazy-load、分享連結、0 則留言 panic 修正。
- **狀態**：本輪已完成 —— 文件更正、bake 鏈接回兩條 build 路徑、本地 x86-64 編譯驗證、GitHub Actions 編譯驗證（run #10，commit `0c5050d`，ghcr + Codeberg 已發布）。#592 已退役；2026-10-23 起加回 #599，現為 6 支；2026-10-27 只動清單中一支的頭（#599 pin 往前推），並補上「清單那欄只是漂移警示」的真相與重現開關（見 `RELEASE_NOTES.md` 2026-10-27 段）。
- **優先級**：P1（已修掉功能缺口，但含一處 breaking 行為需線上確認）。
- 細節：`design/upstream-pr-bake.md`（§2 清單、§5 漂移重做、§7 驗證、§8 風險）。

## P1 — bake 上線後的功能回歸
- **做什麼**：部署新映像後照 checklist 逐項確認（影片 proxy 新格式、0 則留言 permalink、預設 post sort 對新訪客生效、`/u/<user>/s/<id>` 分享連結、圖片 lazy-load），並確認舊影片 proxy 連結 404 的影響可接受。
- **為什麼**：五支 PR 都是 clean merge 且不動依賴，但 clean merge ≠ 語意正確；其中影片 proxy 路徑變更是 breaking。
- **優先級**：P1。
- 細節：`design/upstream-pr-bake.md` §7、§8。

## P2 — Tier 2 上游 PR 的取捨（需決策）
- **做什麼**：逐支決定是否加入 `redlib-prs.txt`：#572（RSS 媒體，取代 #563）、#568（footer 原始碼連結）、#566（geo filter）、#577（Tor onion 入口）、#564（每頁文章數，上游 WIP）、#578（Markdown 回應）。
- **為什麼**：都對現行 main clean-merge；但 #566/#564/#568 會新增 runtime env（需同步 `.env.example` 與 AGENTS.md 變數表），#577 與先前「不採用 fork 的 Tor」決策同類、需明確翻案。
- **優先級**：P2（有價值、可排後；先要決策再動 build）。
- 細節：`design/upstream-pr-bake.md` §3、§4。

## P1 — GitHub 端要設 `CODEBERG_PAT` secret（鏡像 job 的前提）
- **做什麼**：在 GitHub repo → Settings → Secrets and variables → Actions → Repository secrets 新增 `CODEBERG_PAT`，值是 Codeberg 帳號（`Lawlietr`）的 PAT，權限 `write:packages`。只能由帳號持有者操作，agent 拿不到也無法代設。
- **為什麼**：`mirror-codeberg` job 靠它把 ghcr 的成品鏡像到 `codeberg.org/lawlietr/redlib`。沒設時該 job 會 exit 1（刻意不靜默略過），於是 Codeberg 的 tag 就不會更新，而 ghcr 照樣發佈 —— 兩個登錄區會開始不一致。
- **優先級**：P1（不影響 ghcr 主路徑，但 Codeberg 側鏡像全部卡住）。
- 細節：`design/github-actions-workflow.md` §9、`.github/scripts/mirror_to_codeberg.sh`。

## P2 — 在真的 arm64 硬體上跑一下 ghcr 版映像（收尾驗證）
- **做什麼**：在 arm64 機器上 `docker pull ghcr.io/lawlietr/redlib:latest`，起容器後開一個貼文頁確認。
- **為什麼**：ghcr 的 arm64 映像目前只有**靜態證據**：manifest list 有 arm64 entry，`docker cp` 出來的 binary 是 `ELF 64-bit LSB executable, ARM aarch64, statically linked`、無 INTERP、無 dynamic section。本機是 x86_64 且沒有 qemu binfmt（`tonistiigi/binfmt --install arm64` 在此主機無效，`docker run --platform linux/arm64` 會 `exec format error`），所以 arm64 版**尚未實際執行過**。ghcr 版是 glibc 靜態、和 12 機的 musl 版是不同檔案，但**同源碼且 amd64 行為已實測一致**（`/`、`/r/AskReddit/top`、`/r/gaming` 皆 200 與同大小），所以 codeberg 舊 musl 版的實測只能當參考、不能代替 arm64 驗證。CI 的 arm64 閘門有兩層：`docker cp` 出來的 binary 必須 `ARM aarch64` + 零 `NEEDED`（確定性），以及 runner 上
  qemu binfmt 存在時真的起 arm64 容器 —— 後者在 run `39551016403` 實測 `/` 回 200（qemu 模擬下能服務），
  但**這不等於真 arm64 硬體**，本項仍開放。
- **優先級**：P2（CI 與 registry 都已綠燈，只差執行驗證；codeberg 版 arm64 已在真硬體跑過）。
- 細節：`design/github-actions-workflow.md` §5（上線證據與三條路的取捨）。
## P3 — 上游 #560 分享連結的 id 條件錯誤（**已知問題，暫不處理**）
- **做什麼**：**不處理**（2026-10-21 決定），但**必須記得**：在未重新評估之前，任何地方都不能宣稱分享連結已修；要重啟就先重讀 §8.9。
- **為什麼**：上游那支 PR 的 id 長度條件只接受 8–12 字元，而現行 post short id 是 7 字元 → 兩條分享連結入口（subreddit 版與使用者版）對現代 post 一律 404，錯誤頁文字是 `Nothing here`。路由本身有註冊、有在跑（用 8 字元假 id 可探到另一種錯誤），只是條件把人擋在門外。屬上游條件錯誤，不是我們 bake 失手。
- **狀態/優先級**：P3，暫不處理（站外進來的連結壞，但站內使用不受阻）。
- 細節：`design/upstream-pr-bake.md` §8.9（決定性的兩條探測 URL）與 §2 表格的 ⚠ 注記、`design/error-triage-playbook.md` §4.1（路由偵測手法）、`RELEASE_NOTES.md` 的 pre-existing known issue 段。

## 近期完成
- 2026-10-27：**#599 的 pin 往前推（`0db637cd` → `26c02193`）＋揭穿「pin 只是漂移警示」**。上游那支 PR 在我們首次 bake 後多三支 commit：追隨 Reddit 的 `rdt` bot-check 302、留言媒體改原生 `<video>`、以及**直接關乎已發佈映像**的一支——Reddit edge 開始 403 沒帶 `Origin`/`Referer` 的「more comments」POST，且行動端模擬每個 fragment 只給 10 則留言（桌面 25 則）→ 現行正式映像正處於「展開被擋／每頁十則」的退化狀態。新 head 只碰兩個源碼檔、**`Cargo.toml`/`Cargo.lock` 零變化**，六支 `--no-ff` 仍全 clean，並附 4 個新單元測試。驗證（出口可用的機器上跑容器 A/B）：舊 head 229 則留言塊/73 個 More replies vs 新 head 211/70，兩邊都正常 → 「more comments POST 被 403」在我們環境重現不出（上游作者是隨機落到 Chrome 模擬時看到的），但**行動端 vs 桌面**的差距是真實的（同一 fragment：桌面 614KB/132 則 vs Android 266KB/43 則），而舊 head 的 shreddit 请求共用一個啟動時隨機抽平台（Android/Windows）的主 client、每次重啟重抽 → 新 pin 固定桌面 client 是這次最硬的實測理由。留言 permalink + `?context=3`、三種排序各不同、負 control 404、panic 0 全過。順帶定因另一件事：`redlib-prs.txt` 的 SHA 欄**向來只是漂移警示**，建置一律拿 PR 當前 head（用舊 pin 做 A/B 時兩邊其實同一棵樹，image ID 完全相同）→ 新增 `--at-listed-sha`（Dockerfile 端為 `--build-arg BAKE_ARGS=--at-listed-sha`）才能真正重現歷史組合；對消費者的建議是 pin `<git-sha>` tag／digest。另新增 P2 條目「機房出口 IP 的實例：貼文頁全滅，不是 code 問題」。文件同步：`redlib-prs.txt`、`Dockerfile`、`.build/apply_redlib_prs.sh`、`RELEASE_NOTES.md`（新條目）、兩個 README（pin bump 段 + pin 語意 + 故障排除新增兩條）、`design/upstream-pr-bake.md`（§2 表格、§6 腳本說明、§7 checklist、§8.13 新節）、`design/error-triage-playbook.md`（§4.2 新節）。
- 2026-10-23：**bake 上游 #599（貼文頁留言改從 shreddit HTML fragment 重建）**。背景：`0a3e9cd`（v0.40.0）的 `%2F` 繞行已被 Reddit 破掉 —— 線上實例 `/` 與 `/r/popular` 皆 200，但貼文頁 404 + `Failed to parse page JSON data…｜/r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`；上游 main 自 v0.40.0（HEAD `ba116c1`）後零 commit → 上游完全沒修，#599 是 50 支 open PR 中唯一處理此事的（AI 生成、0 review、0 check runs）。先做**靜態分析**（diff 全文阅讀、檔案重疊檢查、相依存在性、`git merge --no-ff` 兩序全 clean），再**本地 x86-64 build + 容器實測**：貼文頁 200 / 206 則正文留言、permalink + `?context=3` OK、留言排序三種集合不同、0 則留言不 panic、panic 0。**已知不完整**（留言 200 則上限、無 author flair/awards、每頁 1–31 請求、冷 3.07s / 熱 0.019s、shreddit cookie session 全實例共用、subreddit 名稱不再被驗證、映像 13.5→14.8MB）。文件同步：`redlib-prs.txt`（pin `0db637cd`）、兩個 README（上游狀態新段 + 故障排除）、`RELEASE_NOTES.md`（逐條 loss 表）、`design/upstream-pr-bake.md`（§2 表格與 merge 順序、§7 新增 #599 專屬項、§8.12）。
- 2026-10-22：**退役 bake 上游 #592（貼文頁 403 繞行）**。上游 v0.40.0（2026-10-22）以直接 commit `0a3e9cd fix: encode anonymous comments request paths` 實作等效 `%2f` 編碼繞行（同碰 `src/client.rs`）；#592 作為 PR 從未合併，保留只會與 `0a3e9cd` 在 `src/client.rs` 衝突，故從 `redlib-prs.txt` 移除，thread-403 改由上游供應。剩餘五支 bake（#549/#542/#521/#560/#539）照常。本輪仍是五支 clean merge、不碰 `Cargo.lock`；本地 build + smoke 全過（`/`、`/r/popular`、`/r/technology`、貼文頁皆 200、negative control 404、panic 0），GitHub Actions run #10（commit `0c5050d`）六 job 全綠並原樣鏡像到 Codeberg（digest 相同）。#592 仍是 workaround 不是 root fix，re-break 風險與 observable（`client.rs` 的 `Reddit blocked this request (403 Forbidden)…`）不變。文件同步：`redlib-prs.txt`、`design/upstream-pr-bake.md`（§2/§7/§8.8）、兩個 README、`RELEASE_NOTES.md`。
- 2026-10-21：**鏡像機制上線**（`.github/scripts/mirror_to_codeberg.sh` + `mirror-codeberg` job）：GitHub 端編譯完、manifest 合併完之後，用 `docker buildx imagetools create` 把 `latest`/`<git-sha>`/`amd64`/`arm64` **原樣複製**到 `codeberg.org/lawlietr/redlib`（registry 側 copy，不重新編譯，blob 約 13MB，**digest 兩邊相同**）；缺 `CODEBERG_PAT` 時 exit 1 明確失敗。文件同步：`design/github-actions-workflow.md` 新增 §9、AGENTS.md、兩個 README 的 Tags/CI/CD/存放位置表、`docker-compose.yaml` 註解、`RELEASE_NOTES.md`。
- 2026-10-21：**煙測上線並全綠**（run `39551016403`，commit `51d0d7e`）：build (amd64)/build (arm64)/manifest/**smoke**/**mirror-codeberg** 五個 job 全成功；smoke 在 runner 上抓到 amd64 與 arm64 binary 皆 `statically linked`、`/` 200 62,216B、`/r/gaming` 200 79,425B、`/r/AskReddit/top` 200 38,012B，qemu 下 arm64 容器 `/` 也回 200；mirror 結尾打印兩邊 child digest 完全相同（`12105bec…` amd64、`d77e9225…` arm64）。第一次嘗試（run `39550258322`）失敗純粹是 smoke job 漏了 `actions/checkout`。
- 2026-10-21：**musl 退場為產品線**（workflow 與 runner 保留不變）。實測對照：ghcr 的 glibc `+crt-static`（`readelf -d` NEEDED=0、13.5MB）與 Codeberg 舊 musl 版（`15cc3c1`、13.2MB）在同一台 x86_64 上 `/`、`/r/AskReddit/top`、`/r/gaming` 全 200 且大小相同、log 無解析器錯誤 —— 靜態 glibc 在 `scratch` 的 NSS/DNS 疑慮未發生，大小也無差異，而 arm64 hosted runner 讓「x86 交叉編 arm64」這個 musl 的唯一理由消失。文件同步把 musl 降調為 `.forgejo/` 備援路的實作細節（兩個 README、AGENTS.md、`design/multi-arch-build.md`、`design/forgejo-runner-workflow.md`、`RELEASE_NOTES.md`），不建平行 tag。
- 2026-10-21：**新增 `smoke` job**（`.github/scripts/smoke_test.sh`，`needs: manifest`；`mirror-codeberg` 改 `needs: smoke`）：對已發佈鏡像做四步：`docker cp` 取出 `:amd64`/`:arm64` 的 `/redlib` 驗證**全靜態**（有 `NEEDED` 即 fail）與 arm64 架構正確 → 起容器打 `/`（200 且 body ≥ 20KB）→ `/r/gaming`、`/r/AskReddit/top`（強迫容器內 DNS + 出網 HTTPS）→ 有 qemu binfmt 時 best-effort 真的起 arm64 容器。reddit 回 403/429 只 warn（機房 IP 限流），>=500 或 log 出現解析器錯誤就 fail。**踩到的坑**：redlib **不收 CLI 參數**，`--help` 會得到 `error: unexpected argument found`，所以別用 `--help` 當存活探測（設定只從環境變數讀）。本機已完整跑過一次（exit 0）。文件：`design/github-actions-workflow.md` §10。
- 2026-10-21：**發佈主權改到 GitHub Actions**。`.forgejo/workflows/build.yml` 的 `push` trigger 移除、只留 `workflow_dispatch`（可填 reason），workflow、runner 與磁碟紀律完整保留作為 fallback 與 musl 產物來源；`codeberg.org/lawlietr/redlib` 的 tag 改由同一條 CI 的 `mirror-codeberg` job 鏡像維護。`ghcr.io/lawlietr/redlib` 成為主要映像來源（雙架構 + `<git-sha>`），README/README_EN 的部署指令、compose 註解、Tags 表、CI/CD 節與 AGENTS.md 全部改寫；新增 README 的「本地編譯與測試」章節（ smoke 四招 + 本機限制：只產本機架構、無 qemu binfmt）；GitHub workflow 加 `concurrency: ghcr-publish` 串行，避免 manifest merge 混到不同 commit 的兩個架構。
- 2026-10-21：**ghcr 也變成雙架構 + 可 pin**（commit `d572b2e`，run `39543407871`，build (amd64) / build (arm64) / manifest 三 job 全綠）。做法是**原生 arm64 hosted runner**（`ubuntu-24.04-arm`，public repo 自 2025-08-07 免費 GA），不用 QEMU、不用交叉工具鏈，arm64 job 全程約 4 分鐘。tag 現在與 codeberg 版完全對齊：匿名 `tags/list` → `latest`/`arm64`/`amd64`/`d572b2e`，且 `latest` 與 `<git-sha>` 都是 `manifest.list.v2`（entries = amd64 + arm64）。新增 `.github/scripts/merge_manifest.sh`（`docker buildx imagetools create`），`build_and_push.sh` 改成吃 `ARCH`。⚠ ghcr 版是 **glibc 靜態** binary（與 12 機的 musl 版是不同產物，digest 不可比）；靜態驗證已做，執行驗證見上方 P2。
- 2026-10-21：**GitHub repo 與 ghcr package 轉為 public**（使用者在 UI 手動翻轉；此前 repo private → package 默默繼承 private，匿名拉取會被 `denied`，很容易誤判成「映像不存在」）。複驗（完全匿名、不帶憑證）：`docker pull ghcr.io/lawlietr/redlib:latest` 成功，digest `sha256:93606cc4…` **與 Actions log（run 39534174002 / commit 15cc3c1）完全一致** → 公開的就是含 #592 那輪；跑起來後貼文頁 200、0 則留言 permalink 200、負 control 404、無 panic。同步把 `design/github-actions-workflow.md` §3/§8 與兩個 README 的 ghcr 段落從「private / 需 `read:packages` token」改為公開現況（仍是 amd64-only、只有 `latest`）。公開後做了 secrets 健檢：全歷史 232 個 blob 掃 token/私鑰 pattern → **0 命中**，`.env.example` 內容全空，CI 只用 `${{ secrets.* }}`。
- 2026-10-21：**逐功能線上核對跑完**（對 `https://ddit.avpclub.uk` 與本地同映像容器）。通過：影片 proxy 的大寫 `CMAF`/`DASH` 路徑（206 `video/mp4`）、舊 `/vid` 路徑 404、0 則留言 permalink 不 panic、`loading="lazy"` 且無 SVG 包裝、路徑式排序正常、預設 post sort 對新訪客生效（用**只抽掉 #521** 的對照映像定因：抽掉後 env 失效）。順帶定因兩個**非回歸**：`?sort=` 向來是 no-op（含/不含 #521 都一樣）、不存在的 sub 回 200 空頁屬上游行為（線上與本地 byte 數一致）。未通過一項：分享連結（見上方 P1 條目）。
- 2026-10-21：**雙架構上線確認** —— amd64 與 arm64 的 redlib container 都已架起來，實測兩個架構都正常運行（跑的是含 #592 的六支 bake 映像）。逐功能線上核對（影片 proxy、panic、post sort、分享連結、lazy-load）仍未做，保留在上方 P1 條目。
- 2026-10-21：**bake 上游 #592 修好貼文頁**（Reddit 對匿名 client 的路徑規則封鎖 → 前端 parse error）。六支 Tier 1 累積 `--no-ff` 全 clean；本地雙映像 A/B 實測（對照組精確重現舊錯誤、含 592 組 200 + 留言正常 + 回歸清單全過）；`redlib-prs.txt` 加行、`upstream-pr-bake.md` §2/§7/§8 同步（§8.8 記錄**繞行**屬性、再壞的觸發條件與 observable 字串）；新增 `RELEASE_NOTES.md`（英文）說明這只是暫緩之計而非真正修正，README 雙語加指針與警告。
- 2026-10-21：**新增 `design/error-triage-playbook.md`** —— 從「貼文頁 parse error」事件沉澱出可重現的溯源 SOP：錯誤訊息→呼叫點映射、上游 PR 基底檢查、**含/不含候選 PR 的雙映像端到端 A/B**（取代裸 curl 探測，後者在無合法 token 時會給假陰性）、固定回歸清單（含負 control 要回正確 404 而非 parse error）、tier 判定與記帳要求（繞行 vs 根治、observable 字串）。
  後續又補了 §4 grep 陷阱（錯誤頁範本自帶 parse error 錯誤訊息文字→假陽性）與 §4.1 逐功能核對四招（素材從站內 HTML 挖、用符合條件的假 id 探路由、對照映像只抽被懷疑的那一支、byte 數一致則屬上游行為）。
- 2026-10-07：**更正 9/18 的 bake 退役判斷**（上游 main 未含那 5 支 PR）；重新接回 bake 鏈，改用上游 PR 取代原 fork port 計畫的 C/D1 子集；新增 `redlib-prs.txt` + `.build/apply_redlib_prs.sh` 供 `Dockerfile` 與多架構腳本共用；兩條 workflow 的觸發路徑補上清單與 `.build/**`；新增 `design/upstream-pr-bake.md`。
- 2026-10-07：**GitHub 遠端上線**（`github.com/Lawlietr/redlib_docker`，private），push 觸發 `.github/workflows/build.yml` 在 `ubuntu-latest` 原生編 amd64 並推 `ghcr.io/lawlietr/redlib:latest`；workflow 補 `packages: write`（首次建立 ghcr package 所需）。文件：`design/github-actions-workflow.md` 全面更新（含與 `.forgejo/` 多架構路的差異表）。
- 2026-09-18：retire 所有 fork patch 與 PR bake（~~上游已全併入 main~~ **此判斷已於 2026-10-07 推翻**，見上條）；`Dockerfile` 改回純 `REDLIB_BRANCH=main` clone；`AGENTS.md` 同步。
- 2026-09-18：repo 結構重整為單一 app（`Dockerfile`/`docker-compose.yaml` 移到 repo 根，目錄名 = 映像名慣例）；`AGENTS.md` 更新慣例與路徑。
- 2026-09-18：多架構 build 上線（Plan B：12 機原生交叉編譯 musl + `Dockerfile.pack` + `imagetools` 合併 manifest list），雙 tag `latest`/`<git-sha>`，推 `codeberg.org/lawlietr/redlib`。文件：`design/multi-arch-build.md`、`design/forgejo-runner-workflow.md`、`design/forgejo-runner-deployment.md`。
- 2026-09-18：文檔同步 —— `design/external-services.md`（cbgproxy 已改 `:9881`、`network_mode: host`、`http_proxy` 白名單、`REDACT_PAT=1`）、`design/ci-workflow.md`（標為存檔，主線改指 `.forgejo/`）。
