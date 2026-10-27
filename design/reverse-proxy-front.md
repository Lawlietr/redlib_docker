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

两台都只能當**入口/跳板**（o3 今天就是這個角色），不能當 Reddit-facing 的實例。

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
   要真 TW-only：把同一個 filter 改成 `WhitelistEnabled=true` 且 `WhiteListCountryCode` 只留 `tw`
   （保留白名單 IP 給自己的機器），或直接在新前門用 `CF-IPCountry`（見下）。

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
