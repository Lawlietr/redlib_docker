# 前門（反向代理）與出口 IP：誰被封、誰沒被封

這份文件回答一個很容易搞混的問題：**「同一條 bake 出來的映像，為什麼 A 台能用、B 台不能用？」**
答案幾乎總是在**出口（egress）**那一側，而不是在**入口（inbound / 反向代理）**那一側。

---

## 1. 兩條 leg，兩個 IP —— Reddit 只看其中一條

以 `https://ddit.avpclub.uk/` 的現行拓撲（2026-10-27 用命令證明，不是推測）：

```
瀏覽器
  │ HTTPS
  ▼
Cloudflare（ddit CNAME → o3.avpclub.uk，proxied=true；orange cloud）
  │ HTTPS（Zoraxy  termination，且 zoraxy 的 trusted_proxies.json 內含 CF 全網段）
  ▼
o3（o3PublicIP，Oracle Tokyo AS31898）
  │  zoraxy_o3 容器（:80/:443/:8000），规则檔：
  │  /root/zoraxy/config/conf/proxy/ddit.avpclub.uk.config
  │    ActiveOrigins   = someZT:8080      ← 123（Ubox-02）的 ZeroTier IP
  │    InactiveOrigins = 10.0.0.134:8084（舊 123 IP，已死）、
  │                      o1ZT:8084（o1 的 redlib，weight 0）、
  │                      o1ZT:8095（o1 的 checkupdate 測試實例）
  │ ZeroTier（net ZeroTierNetID，10.147.17.0/24）
  ▼
123（192.168.1.123 / zt someZT）→ redlib 容器 :8080（ghcr :latest，image id de587d3a2be3）
  │
  │  ★ 只有這條 leg 是 Reddit 看得見的：123 的台灣住宅/辦公室出口
  ▼
reddit.com（listing 走 /r/<sub>，留言走 /svc/shreddit/comments/...）
```

- **入口 leg**（瀏覽器 → CF → o3 → ZeroTier → 123）：**Reddit 完全看不到**。走 o3、走 o1、走 nx、走 Cloudflare Tunnel 都一樣，不影響任何封鎖判定。
- **出口 leg**（跑 redlib 的那台 → reddit.com）：**這才是 Reddit 用來判封鎖的 IP**。
- 所以「反代在哪台 = Reddit 看到的 IP」這個直覺是**錯的**；決定成敗的是「**redlib 這個行程跑在哪台**」。

### 證明用的實測（2026-10-27）

| 探測點 | 目標 | 貼文頁結果 |
|---|---|---|
| 本地（TW 出口） | `https://ddit.avpclub.uk/r/comics/comments/1xgpbes/x/`（origin = **123**） | **200 / 150,701 B / 128 則留言**；`/r/thisecommercelife/…1wakyfh` 200 / 28,742 B / 9 則 |
| 123 本機 | `http://127.0.0.1:8080/r/comics/comments/1xgpbes/x/` | **200 / 154,242 B / 130 則**（3.42s）；`docker stats`：`42.78MiB / 256MiB`、CPU 0%（idle） |
| **o1** 本機 | `http://127.0.0.1:8084/...`（redlib，舊 pin `73900bee`） | **404 / 0 則**，`Reddit returned 403 Forbidden \| /svc/shreddit/comments/r/comics/t3_1xgpbes` |
| **o2** 本機（新 digest `03c5b28c…`，臨時探測容器） | `http://127.0.0.1:8086/...` | **404 / 0 則**，同上一字不差（三條貼文皆同） |
| **o3** 本機 | `http://127.0.0.1:8084/...` | **404 / 0 則**，同上 |
| 三台的 listing | `/r/comics/top/?t=month` | **都 200 / 49,099 B** → 封鎖是**路徑規則**，不是整台被封 |

三台雲主機（o1 `o1PublicIP`、o2 `o2PublicIP`、o3 `o3PublicIP`）經 `ipinfo.io` 全是
**`AS31898 Oracle Corporation`，Tokyo**，同一家雲的同一個出口群 → 同一條 `/svc/shreddit/` 路徑規則把它們全打死。

> ⚠ 不要用 `curl https://www.reddit.com/...` 判別封鎖：三台裸 curl **連列表都 403**（UA-based），
> 但同一台的 redlib 列表 200。裸 curl 在此環境完全不可靠（playbook §3 的舊結論，這次又成立）。

---

## 2. o1 / o2 能不能跑 redlib？

**資源面：完全可以**（redlib 是 14.8MB 的靜態二進位、idle RSS 約 43MB）；
**但 Reddit 面：不能**——它們的出口被 shreddit 路徑打死，跑起來就是「列表正常、所有貼文頁 0 留言」的幽靈實例。

| 項目 | o1（first01） | o2 |
|---|---|---|
| 公網 IP / AS | o1PublicIP / AS31898 Oracle Tokyo | o2PublicIP / AS31898 Oracle Tokyo |
| OS / kernel | CentOS 7（3.10.0-1160） | CentOS 7（3.10.0-1160） |
| vCPU / load | 2 / 0.33 | 2 / 0.17 |
| RAM | 985MB total，525MB available（+8GB swap，已用 68MB） | 985MB total，**385MB available**（swap 已用 204MB） |
| 磁碟 | 39G，**33G free**（16%） | 39G，**27G free**（31%） |
| Docker | 23.0.1，overlay2，cgroup v1 | 26.1.4，overlay2，cgroup v1 |
| 現在跑 redlib？ | **是**：`redlib`（`codeberg.org/lawlietr/redlib:latest`，舊 pin，`0.0.0.0:8084`）+ `redlib-cu-test`（`o1ZT:8095`） | 否（我這輪起了臨時探測容器 `:8086`，測完已刪） |
| 結論 | **不該跑**（出口被封 + 舊 pin + 裸 IP 公開） | **不該跑**（出口被封；RAM 較緊但足夠） |

兩台都只能當**入口/跳板**（o3 今天就是這個角色），不能當 Reddit-facing 的實例。

---

## 3. 顺帶查出來的兩個暴露面（建議處理）

1. **o1 與 o3 的 redlib 都在裸 IP 上以 HTTP 公開**：`http://o1PublicIP:8084/` → 200、
   `http://o3PublicIP:8084/` → 200（從外部機器直接可達）。o1 那台還是**舊 pin、貼文頁全壞**的幽靈實例。
   → 建議把 port 綁到 ZeroTier/LAN（`10.147.17.x:8084:8080` 或 `192.168.1.x`），或直接把 o1 的 redlib 停掉、
   把 Zoraxy 的 `InactiveOrigins`（`10.0.0.134:8084`、`o1ZT:8084`、`o1ZT:8095`）清乾淨。
2. **ddit 的「Taiwan Only」其實是黑名單，不是白名單**。Zoraxy 掛在 ddit 上的 access filter
   （UUID `ZoraxyFilterID-4977-4288-825b-0d5ab817f670`，Name `RU CN MX Blacked`，Desc `Taiwan Only`）實際內容是：
   `BlacklistEnabled=true`、`BlackListContryCode={cn,mx,ru}`、`WhitelistEnabled=false`。
   → 實測從 o3（JP 出口）打 `https://ddit.avpclub.uk/` 得 **200 / 60,703 B**，**JP/US/DE 等都進得來**。
   要真 TW-only：**先**打開那條 access filter 的 **Trusted Proxy Gating**（見 §3.3，不做這步的話白名單會連你自己都擋），
   再把 `WhiteListCountryCode` 留 `tw`（+自己的 IP 白名單）；或改在新前門用 `CF-IPCountry`（見 §4）。

---

### 3.3 「TW 白名單反而把自己擋掉」的根因：access filter 不看 CF 標頭（實測＋原始碼雙重證明）

2026-10-27 重現（同一台 o3、同一條 `Taiwan White` filter，UUID `b6f4dd52-…`，掛在 `note.avpclub.uk` 上；
該 filter 內容 = `WhitelistEnabled=true`、`WhiteListCountryCode={tw}`、`WhiteListIP={她的自宅公網IP/32}`、
`WhitelistAllowLocalAndLoopback=false`、`TrustProxyHeadersOnly=false`）：

| 探測路徑 | TCP socket 對端 | Zoraxy 判定用的 IP | 結果 |
|---|---|---|---|
| 本地 TW 出口 `她的自宅公網IP` → **Cloudflare** → `https://note.avpclub.uk/` | CF 邊緣節點 | **CF 邊緣節點** | **403 Zoraxy Forbidden**（即使 `她的自宅公網IP/32` 就在白名單裡） |
| 同一台機器 `--resolve note.avpclub.uk:443:o3PublicIP`（**繞過 CF**） | `她的自宅公網IP` | 你的真實 IP | **200** |
| o3 本機 loopback（`--resolve …:443:127.0.0.1`） | `127.0.0.1` | loopback | **403**（`WhitelistAllowLocalAndLoopback=false`） |
| 同一時刻 `ddit`（掛黑名單 filter）走上述三路徑 | 同上 | 同上 | 200 / 200 / 200 |
| 403 發生時在 origin 端被動抓封包（`tcp port 3003`） | — | — | **0 個 GET** → 擋在 Zoraxy，不是應用層 |

根因在 Zoraxy 解析 client IP 的那個函式（`tobychui/zoraxy`：`src/mod/access/trustedProxy.go:191`）：

```go
func (s *AccessRule) GetClientIP(r *http.Request) string {
    remoteIP := netutils.GetRequesterIPUntrusted(r)       // 只看 TCP socket 對端
    if s.TrustProxyHeadersOnly && s.parent != nil && s.parent.IsTrustedProxy(remoteIP) {
        return netutils.GetRequesterIP(r)                 // 只有這時才讀 X-Real-IP / CF-Connecting-IP / XFF
    }
    return remoteIP                                       // 否則一律用 socket IP
}
```

- 她的 filter 裡 **`TrustProxyHeadersOnly: false`**（舊 filter 乾脆沒有這個欄位；`src/mod/access/access.go:44` 預設 false）
  → 走 Cloudflare 時 socket 對端是 **CF 邊緣節點**，而 geodb（`conf/geodb/geoipv4.csv`，2026-05-06 版）把那些段成
  **US / NL / AU / CR**。實測例：我看到的對端是 `172.68.228.140`（∈ `172.64.0.0/13`）→ 既不是 `tw`、也不在她的 IP 白名單 → 一律 403。
- geodb 對各段的判定（同一份 CSV，用 python 查）：`她的自宅公網IP → TW`、`1.200.0.1 / 111.240.x / 36.230.x → TW`、
  `173.245.48.5 / 104.16.x / 198.41.128.1 / 188.114.96.1 → US`、`141.101.64.1 → NL`、`162.158.1.1 → AU`、
  `190.93.240.1 / 131.0.72.1 → CR`、`10.147.17.x → NA`（private）。
- **CF 確實把真實 client 送進來了**：在 o3 上抓 `tcp port 8080`（Zoraxy → origin）看到
  `X-Forwarded-For: 她的自宅公網IP, 172.68.228.140` —— 第一段是 CF 眼中的你，第二段是 Zoraxy 自己附加的 socket 對端。
- `conf/trusted_proxies.json` 已內含完整 CF 網段（15 個 v4 + 7 個 v6），所以 gating 一開就會走到 `GetRequesterIP()`，
  讀 `CF-Connecting-IP`（CF 一律送）或 XFF 最左段 → 得到真實 client。
- 比對邏輯本身沒問題：`src/mod/access/accessRule.go:90 IsWhitelisted()` = **國家（geodb）或 IP（wildcard／CIDR）任一命中即放行**；
  國家碼一律 `strings.ToLower`（`tw` 小寫正確）；`netutils.MatchIpCIDR` 支援 `她的自宅公網IP/32`。

**修法（在她自己的 Zoraxy UI 做，別用文字編輯器改 JSON：真值在加密的 `sys.db`，352MB）**
1. Access Control → 選那條 filter → **Enable Trusted Proxy Gating**
   （UI 原文：*"Only trust X-Real-IP or X-Forwarded-For headers from trusted proxy listed in the whitelist advanced settings"*；
   endpoint `/api/whitelist/trustProxy`）。
2. 要讓 ZeroTier／LAN 也進得來：開 **Enable LAN and Loopback**，或在 IP 白名單加 `10.147.17.0/24`（比開 loopback 精準）。
3. 白名單留 `tw` + 自己的固定出口 IP；之後非 TW 訪客才會真的被擋。

**2026-10-27 修好之後的複測**（她把 gating 開起來，而且把 `Taiwan White` 掛到了 `ddit`）：
兩條 filter 現在都是 `TrustProxyHeadersOnly: true`（`b6f4dd52` 13:33:46 UTC；`ZoraxyFilterID` 一併開），
`ddit.avpclub.uk.config` 的 `AccessFilterUUID` 已改成 `b6f4dd52`（rule 檔 13:32:38 UTC）。複測矩陣（全部實測）：

| 路徑 | 結果 | 判讀 |
|---|---|---|
| TW 出口 `她的自宅公網IP` → CF → `ddit` | **200 / 62,560 B** | 白名單放行（tw + 這個 IP） |
| TW 出口 → CF → `note` | **200**（修之前是 403） | 白名單生效且不再誤擋 |
| o3 公網出口（JP）→ CF → `ddit`／`note` | **403 / 403**，log：`[router:whitelist] [client: o3PublicIP] curl/7.68.0` | 非 TW 現在真的被擋 |
| 裸 IP 直連 o3（`https://o3PublicIP/` + `Host: ddit…`） | **403** | 同一條規則也蓋住裸 IP 進入 |
| **123 走 ZeroTier 直連 o3（SNI=ddit）** | **403** | ⚠ 內部線路被擋：`10.147.17.0/24` 不在白名單、`WhitelistAllowLocalAndLoopback=false` |
| o3 loopback（`--resolve …:443:127.0.0.1`） | **403** | ⚠ 健康檢查／本機排障也進不去 |
| o1／o2（CentOS 7，curl 7.29）→ CF | `http=000`（TLS 交握失敗） | 不是封鎖，是舊 curl 與 CF 交握不了；別拿這兩台的 curl 當探針 |

**因此現在要處理的兩個副作用**：
1. **break-glass 消失了**：ZeroTier／LAN／loopback 進 `ddit` 這類掛白名單的站會 403。建議在白名單加
   `10.147.17.0/24`（比開 loopback 精準），或改開 **Enable LAN and Loopback**。
2. **JP 出口的監控會開始回報失敗**：Uptime Kuma／Beszel 若在 o1/o2/o3 打 `ddit`，現在會拿到 403
   （log 今天出現過非 TW 的 `client: 34.6.126.9`×16、`45.138.12.58`×6、`104.30.167.164`×2）。
   解法：把它們的出口 IP 加進白名單，或讓監控直打 `123:8080`（走區網／ZT，不經前門）。

**連帶結論（不太舒服但重要）**：`ddit` 當時掛的 `RU CN MX Blacked` 也沒有開 gating（2026-10-27 已連同白名單一起修正），所以那條「黑名單 CN/RU/MX」在很長一段時間裡
兩年來實際上判的是 **CF 邊緣節點**的國家（US/NL/AU/CR），既沒擋到 CN/RU/MX 訪客、也幾乎不會擋到任何東西 ——
我 2026-10-27 從 JP 出口打得進 200 就是這個原因，而不是「JP 被允許」。
**放在 Cloudflare 後面的國家黑/白名單，沒開 Trusted Proxy Gating ＝ 沒有在過濾。**

**Access log 的位置（我 2026-10-27 一開始判斷錯了，這裡更正）**
- 請求記錄**本來就在寫**，沒有「要打開」這回事：寫進 `config/log/zr_<YYYY>-<M>.log`（`LogHTTPRequest`，
  `src/mod/info/logger/trafficlog.go:21`）。我看到 `zr_2026-10.log` 0 bytes 就以為沒在記 —— 錯了，
  內容在**輪轉檔** `zr_2026-10.log.1`（41MB）與 `zr_2026-10.log.2.gz` 裡面。
- `conf/log_conf.json`（UI 上的 **Log Settings → Enable Log Rotation**，欄位 `enabled`／`maxSize`／`maxBackups`／`compress`）
  只管**輪轉**，不是「要不要記 access log」的開關（`src/mod/info/logger/handle.go` 的結構註解寫的就是 rotation）。
  `maxSize` 為 `"0"` 時代碼會改用預設 25MB（`ApplyLogConfig`），所以沒設定過的結果就是 log 長到 40 多 MB 才切。
- 真正控制「這條 rule 記不記」的開關在 **rule 編輯器最下面**：**Disable Requests Logging**（勾起來才不記）
  與 **Disable Statistic Collection**（只關統計、仍照記 log）。她 ddit／note 兩條都是未勾＝有記。
- UI 看 log 的入口：Log Settings 同頁的 **Open Log Viewer**（`/snippet/logview.html`，列出 zr_* 檔、可篩選與下載）。
  命令列則用：
  ```sh
  L=/root/zoraxy/config/log
  grep -a "router:whitelist" $L/zr_2026-10.log.1 | tail        # 被白名單擋的 403（黑名單是 router:blacklist）
  grep -a "origin:ddit.avpclub.uk" $L/zr_2026-10.log.1 | grep -a 2026-10-27 \
    | grep -oaE "client: [0-9.]+" | sort | uniq -c | sort -rn | head    # 各 client 命中次數
  ```
- ⚠ 她這版（`zoraxydocker/zoraxy:latest`，image built 2026-06-09）log 行裡的 `[client: …]` **不能當作
  「filter 用哪個 IP 判定」的證據**：13:11 那筆 `note` 的 403 印的是 `[client: 她的自宅公網IP]`（真實 client），
  但那時 gating 還關著、filter 判的其實是 CF 邊緣節點。可信的是 **reason 標記**（`router:whitelist`／`router:blacklist`）
  加上實測 A/B。上游 main 已經讓 log 也走 gating-aware 解析（`proxyRequestHandler.go:394`），升級後兩者才會一致。


---

## 4. 若要搬回本地前門（nx = NGINX-UI 那台）——可用的配方

nx（`192.168.1.17`，zt `someZT`，Ubuntu 24.04，nginx 1.24.0，**geoip2 dynamic module 已裝**，
768MB RAM / 296MB available / 3G quota 已用 62%，load 2.4–3.1 on 2 vCPU）已經是 `ente` / `minio` / `doh`
等 `*.avpclub.uk` 的 origin，**通配證就在 `/etc/nginx/ssl/*.avpclub.uk_avpclub.uk_EC256/fullchain.cer`**，
入口是 `hm` = `她的自宅公網IP`（台灣 Hinet 公網 IP，proxied=true），經路由器 port-forward 進 nx。
nx 到 123 的 redlib 兩條路都通：`http://192.168.1.123:8080` → 200、`http://someZT:8080` → 200。

**需要的 DNS 只有一行**（我可用 CF API 做，但動 DNS 前想先給你確認）：
`ddit` CNAME `o3.avpclub.uk` → `hm.avpclub.uk`（保持 proxied=true；`o3` 上的 Zoraxy 規則留著當備援，不用删）。

nx 上的 vhost（可直接貼；TW 過濾用 **`CF-IPCountry`**，比 GeoIP 準且免-db，GeoIP 只當直連 fallback）：

```nginx
# /etc/nginx/conf.d/ddit.avpclub.uk.conf
# 只有透過 Cloudflare 進來的請求才可信 CF 標頭；直連（LAN/ZeroTier）走自己的判斷
map $http_cf_ipcountry $ddit_cc {          # CF 在 proxied 記錄注入的兩字國家碼
    default        "";
    ""             "";                      # 沒有標頭 = 非 CF 直連
}
geo $ddit_from_cf {                         # 來源是不是 CF 的出口段（nx 目前沒有 set_real_ip_from，補上）
    default                0;
    173.245.48.0/20        1;  103.21.244.0/22   1;  103.22.200.0/22   1;
    103.31.4.0/22          1;  141.101.64.0/18   1;  108.162.192.0/18  1;
    190.93.240.0/20        1;  188.114.96.0/20   1;  197.234.240.0/22  1;
    198.41.128.0/17        1;  162.158.0.0/15    1;  104.16.0.0/13     1;
    104.24.0.0/14          1;  172.64.0.0/13     1;  131.0.72.0/22     1;
}
geo $ddit_private {                         # LAN / ZeroTier / WireGuard 一律放行（管理用）
    default          0;
    192.168.1.0/24   1;
    192.168.100.0/24 1;
    10.147.17.0/24   1;
    100.64.0.0/10    1;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ddit.avpclub.uk;
    ssl_certificate     ssl/*.avpclub.uk_avpclub.uk_EC256/fullchain.cer;
    ssl_certificate_key ssl/*.avpclub.uk_avpclub.uk_EC256/private.key;

    # TW-only：CF 標頭優先；非 CF 直連再用 GeoIP（GeoLite2-Country.mmdb，需 MaxMind licence）
    set $ddit_allow 0;
    if ($ddit_private)   { set $ddit_allow 1; }
    if ($ddit_from_cf)   { set $ddit_allow 2; }
    if ($ddit_cc = "TW") { set $ddit_allow 1; }
    if ($ddit_allow = 2) { set $ddit_allow 0; }          # 從 CF 來但國家碼不是 TW → 回到底層判斷
    if ($ddit_cc = "TW") { set $ddit_allow 1; }
    if ($ddit_allow = 0) { return 403; }                 # 保留 LAN/ZT 白名單與 TW

    location / {
        proxy_pass http://192.168.1.123:8080;            # 走區網；ZT someZT:8080 為備援
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header CF-IPCountry      $http_cf_ipcountry;
        proxy_read_timeout 60s;                          # 大討論串 cold 可到 3–4s，留餘裕
        add_header X-Reddit-Egress "123/ubox-02" always; # 排障用：一眼看出出口是哪台
    }
}
server { listen 80; listen [::]:80; server_name ddit.avpclub.uk; return 301 https://$host$request_uri; }
```

搬之前要留意的三件事：
1. **nx 沒有 `set_real_ip_from` / `real_ip_header`**（查過 `nginx.conf`、`conf.d`、`sites-enabled`、`snippets` 全無），
   所以 `$remote_addr` 在 CF 進來時會是 CF 的 IP → **國家判斷只能用 `CF-IPCountry`**；要_geoip 對直連生效就要先補
   `set_real_ip_from <CF ranges>; real_ip_header CF-Connecting-IP;`。
2. nx 的 GeoIP 資料庫是舊的 **GeoIP v1**（`/usr/share/GeoIP/GeoIP.dat`，2024-04），`ngx_http_geoip2_module.so`
   已裝但**沒有 GeoLite2 mmdb**（MaxMind 現在要 licence key）。所以別假設 GeoIP 現成可用。
3. 搬前門**不會**改變 Reddit 看到的 IP（出口仍是 123）。它的價值只有：自己控制過濾規則、不依賴 o3 當入口、
   少一跳到 JP。代價：多一台 2 vCPU/768MB、load 已經 2.4–3.1 的機體進入關鍵路徑。

---

## 5. 這輪的處置與未處置

- **沒動任何 DNS、沒動 o3 的 Zoraxy 規則、沒關任何 port**（這些屬於會打到正式服務的動作，等你在
  下面兩項之間做決定）。
- 唯一動過的正式動作（本輪較早、為了排除「版本沒更新」這個變數）：用 Komodo stack 路徑
  `docker compose pull && up -d` 把 **123** 與 **o3** 的 redlib 都換成新 pin 的 digest，並用
  `docker inspect` 的 `running_id` 驗證。123 現在是 ddit 的 origin（`someZT:8080`）、
  貼文頁實測 130 則留言；o3 的那個容器現在**不在任何 ddit 路徑上**（只剩裸 IP 可達，見 §3.1）。
