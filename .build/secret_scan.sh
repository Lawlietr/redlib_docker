#!/usr/bin/env bash
# secret_scan.sh — 這個倉庫是**公開**的（GitHub + Codeberg 兩邊都是 public mirror），
# 所以任何 token / key / PAT / 憑證 / 內部識別碼 / 住宅 IP 都不准進 git。
# 機敏細節一律放 private repo（o3_stuffs），這裡只用「路徑 + 描述」引用。
#
# 用法：
#   .build/secret_scan.sh              # 掃 working tree（追蹤中的檔案）
#   .build/secret_scan.sh --history    #  additionally 掃所有 commit 的 blob（慢，但發現在歷史裡的东西）
#   .build/secret_scan.sh --soft       # 有命中也回 0（給 CI 觀察用；預設回 1）
#
# 要豁免某一行：在該行尾加 `scan-ignore`（例：範例 placeholder）。
# 教訓來源：2026-10-27 另一輪工作把 cloudflared 的 connector token、code-server 的明文密碼
# 印進工具輸出，也一度把「住宅 IP／access-filter UUID／ZeroTier 主機位址」寫進這個公開倉庫的
# 文件。那些不是 token，但同樣是可用來定位與攻擊的識別碼，所以一樣擋。
set -euo pipefail

cd "$(dirname "$0")/.."

HISTORY=0
SOFT=0
for a in "$@"; do
  case "$a" in
    --history) HISTORY=1 ;;
    --soft)    SOFT=1 ;;
    *) printf 'unknown arg: %s\n' "$a" >&2; exit 2 ;;
  esac
done

# 每列一個 ERE。注意：這是「找可疑值」，不是找「變數名」。
PATTERNS=(
  'eyJ[A-Za-z0-9_-]{20,}'                                   # JWT（cloudflared connector token、CF API token 都是這個形狀）
  'gh[pousr]_[A-Za-z0-9]{16,}'                              # GitHub token
  'github_pat_[A-Za-z0-9_]{16,}'                            # GitHub fine-grained PAT
  'glpat-[A-Za-z0-9_-]{16,}'                                # GitLab PAT
  'xox[baprs]-[A-Za-z0-9-]{10,}'                            # Slack
  'AKIA[0-9A-Z]{16}'                                        # AWS
  'ocid1\.[a-z]+\.[a-z0-9-]+\.[a-z0-9]+\.[A-Za-z0-9]{30,}'   # Oracle Cloud OCID
  'BEGIN [A-Z ]*PRIVATE KEY'                                # key material
  '-----BEGIN CERTIFICATE-----'                             # 憑證本體（放 repo 等於把內部 CA 暴露）
  '(pass(word|wd)?|secret|token|api[_-]?key|access[_-]?key|authorization|bearer|hash)[^A-Za-z0-9]{0,4}["'"'"']?[A-Za-z0-9_+/=-]{20,}'
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'  # UUID（內部 group id、tunnel id 等識別碼）
  '(^|[^0-9])10\.147\.17\.[0-9]+([^0-9]|$)'                 # ZeroTier 主機位址（只准留 10.147.17.0/24 這種網路寫法）
  '(^|[^0-9])106\.104\.112\.[0-9]+([^0-9]|$)'               # 自宅公網 IP（她的住宅線路）
)

# 這些是合法的「同名但非值」寫法，命中也不算外洩
ALLOW='\$\{\{[[:space:]]*secrets\.|scan-ignore|sha256:[0-9a-f]{12,}|<[^>]{3,}>|10\.147\.17\.0/(16|24)|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-0000'

found=0
scan_file() {  # $1 = 顯示用的標籤, $2 = 檔名或 blob 標籤, 內容從 stdin
  local label="$1" src="$2" content hits
  content="$(cat)"
  for p in "${PATTERNS[@]}"; do
    hits="$(printf '%s\n' "$content" | grep -nE "$p" 2>/dev/null | grep -vE "$ALLOW" || true)"
    if [ -n "$hits" ]; then
      found=1
      printf '%s命中 [%s] %s:\n' "$label" "$p" "$src"
      printf '%s\n' "$hits" | sed 's/^/    /' | cut -c1-160
    fi
  done
}

if [ "$HISTORY" = "1" ]; then
  for rev in $(git rev-list --all); do
    for f in $(git ls-tree -r --name-only "$rev"); do
      case "$f" in
        .build/secret_scan.sh|*.png|*.jpg|*.ico|*.woff*|*.tar*|*.zst|*.gz) continue ;;
      esac
      scan_file 'HISTORY ' "${rev:0:8}:$f" < <(git show "$rev:$f" 2>/dev/null | tr -d '\0')
    done
  done
fi

while IFS= read -r f; do
  case "$f" in
    .build/secret_scan.sh|*.png|*.jpg|*.ico|*.woff*|*.tar*|*.zst|*.gz) continue ;;
  esac
  scan_file 'WORKTREE ' "$f" < <(cat "$f" 2>/dev/null | tr -d '\0')
done < <(git ls-files)

if [ "$found" = "1" ]; then
  printf '\n✗ 找到上述類型的值。公開倉庫不准這些：改写成「值在 private repo o3_stuffs」之類的引用，\n'
  printf '  或在那一行加 scan-ignore（只在真的是 placeholder 時用）。\n'
  [ "$SOFT" = "1" ] && exit 0
  exit 1
fi
SUMMARY_SUFFIX=""
if [ "$HISTORY" = "1" ]; then SUMMARY_SUFFIX=" 與 history"; fi
printf '✓ secret_scan：working tree%s 沒有看到 token/key/OCID/UUID/住宅 IP/ZT 主機位址\n' "$SUMMARY_SUFFIX"
