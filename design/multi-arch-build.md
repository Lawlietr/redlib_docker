# 多平台建置（amd64 + arm64）— 實施要領

> 優先級 **P0**。本檔記錄「怎麼做」；工作進度見 `TODO.md`。
> 機敏資訊（`CODEBERG_PAT`）只放在 repo secret，不寫入本檔。

## 1. 目標

把現行**單一 amd64** 映像改為**兩平台**，並用一份 `latest` manifest list 讓
`docker pull` 自動偵測架構：

- `linux/amd64`     ← `x86_64-unknown-linux-musl`
- `linux/arm64`     ← `aarch64-unknown-linux-musl`（樹莓派 3/4 64-bit）

推送目標：`codeberg.org/lawlietr/redlib`（namespace 全小寫，docker 規則）。

## 2. 現況（改動前）

- Dockerfile：builder 用 `rust:1.98-slim-bookworm`（glibc），**在 Dockerfile 內**
  用 `cargo rustc … +crt-static/relocation-model/static/link-args=-static` 出
  **amd64 全靜態 glibc binary**；release 用 `scratch`。
- `.forgejo/scripts/build_and_push.sh`：`docker build --platform linux/amd64` 單檔。
- workflow 觸發：僅 `paths: [ "Dockerfile" ]`。

## 3. 架構決策：Plan B（原生交叉編譯 + imagetools 合併）

選 **B**（原生交叉、無 QEMU、sequential 低峰值，適合 12 機 i9 + 30GB）。

流程：

```
build script（host，redlib:host label）
  對每個 arch：
    cargo build --release --target <triple>      # 原生，i9 快
    複製 binary → 該 arch 的打包目錄
    docker build --platform <p> -t img:<arch> -f Dockerfile.pack .
    docker push img:<arch>
    docker image prune -a -f                      # 逐檔 prune，壓峰值
  兩檔都 push 後：
    docker buildx imagetools create -t img:latest -t img:<sha> \
        img:amd64 img:arm64                         # 合併成 manifest list
    docker push img:latest img:<sha>              # 推 manifest
```

為什麼不用 buildx `--platform all --push`（Plan A）：
- x86_64 機上 arm64 會跑 **QEMU 模擬**，速度較慢。
- `--platform all` 一次留兩張暫存映像，**峰值碟可能衝破 30GB**。Plan B 逐檔
  build/push/prune 把峰值壓在單個 build，30GB 很穩。

## 4. target / libc 子決策

- **B1（已定案）：兩檔統一 musl 靜態。** musl target 的 `+crt-static` 是 Rust 預設，
  不用手搓靜態 flag。match upstream、一套 flag、最乾淨。**amd64 從 glibc 改為 musl**，
  但 redlib 無 glibc 專屬需求，風險低，改完重測即可。

## 5. 工具鏈（12 機 runner）

> **所有工具鏈安裝與建置操作全在 12 runner（Ubox-02 `forgejo-runner` 容器）執行。**
> **本地（Code-Agent-01）不裝任何工具鏈、不碰本地 Forgejo。**
> runner 映像基底為 `rust:1.98-slim-trixie`（Debian 13 trixie, glibc 2.41），
> 需完整安裝 musl-cross-make aarch64-musl toolchain、clang、docker CLI 等。

runner Dockerfile 需增加的套件（`/opt/forgejo-runner/Dockerfile`，`apt-get install -y --no-install-recommends`）：

```
# musl cross-compiler：從 musl-cross-make 建構（aarch64-linux-musl-gcc/g++/ar）
# Debian trixie 的 musl-tools 只提供 amd64 musl wrapper，無法 cross-compile arm64
# cross-compiler：glibc cross（用於 bindgen 解析 glibc headers）
gcc-aarch64-linux-gnu \
# bindgen 需要 clang/libclang（dlopen libclang）
clang libclang-dev \
# cmake 是 boring-sys2 build script 的依賴
cmake \
# g++ make（boring-sys2 C++ source 需要）
g++ make \
# nodejs npm（actions/checkout 需要）
nodejs npm \
# docker CLI（trixie 的 docker.io package 不含 CLI，需從 Docker official repo 或 binary 安裝）
docker.io \
# git ca-certificates（git clone + TLS）
git ca-certificates
```

bindgen 需要 glibc multiarch headers（Debian trixie: `/usr/include/x86_64-linux-gnu`），
需在 Dockerfile 中建立 symlink：
```
RUN ln -sf x86_64-linux-gnu/bits /usr/include/bits && \
    ln -sf x86_64-linux-gnu/sys /usr/include/sys && \
    ln -sf x86_64-linux-gnu/asm /usr/include/asm
```

`build_and_push.sh` 需設定 `BINDGEN_EXTRA_CLANG_ARGS="-I/usr/include/x86_64-linux-gnu --target=x86_64-unknown-linux-gnu -D__LP64__"`。

rust target（`rustup target add` 兩個，裝在 runner 容器內）：
```
x86_64-unknown-linux-musl
aarch64-unknown-linux-musl
```

rust target（`rustup target add` 兩個）：
```
x86_64-unknown-linux-musl
aarch64-unknown-linux-musl
```

編譯指令（upstream 實測有效的寫法，env 只設 linker/CC）：
```bash
export CC_aarch64_unknown_linux_musl=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc

cargo build --release --locked --target x86_64-unknown-linux-musl
cargo build --release --locked --target aarch64-unknown-linux-musl
```

> **`CXX_*`/`AR_*` 必要**：boring-sys2 帶一個 C++ 來源（`encrypted_client_hello.cc`）。
> `cc` crate 若沒見 `CXX_<target>` 會回退到 **host `g++`（x86_64）** 去編，產生
> x86_64 的 `.cc.o`，arm64 linker 報 "file in wrong format (EM: 62)"。
> `build_and_push.sh` 已設 `CC_*`+`CXX_*`+`AR_*`（2026-09-19 commit `fc555ee`）。
> 實測：amd64 只需 `CC_*` 就能過；arm64 不補 `CXX_*`/`AR_*` 必敗。


## 6. 打包：Dockerfile.pack（薄打包，不編譯）

每個 arch 的 binary 已預先編好，Dockerfile.pack 只負責包進 `scratch`：

```dockerfile
FROM scratch
COPY <arch>-redlib /redlib
EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s \
  CMD wget --spider -q http://localhost:8080/settings || exit 1
CMD ["/redlib"]
```

musl/glibc 全靜態 binary 都自包含，`scratch` 可直接跑（跟現在 amd64 一樣）。

## 7. 多 tag 方案

單次 build 產生並推送：

| tag | 類型 | 用途 |
|-----|------|------|
| `latest` | manifest list（兩平台） | 主用，`docker pull` 自動偵測架構 |
| `<version>` / `<git-sha>` | manifest list | 固定可重現的 pin |
| `amd64` / `arm64` | 單檔 | 明確 pull / 除錯 |

`latest` 與各平台 tag 並存。用 `imagetools create` 一次產出 `latest` + `<sha>`：
```bash
docker buildx imagetools create \
  -t "${IMAGE}:latest" -t "${IMAGE}:${GIT_SHA}" \
  "${IMAGE}:amd64" "${IMAGE}:arm64"
```

## 8. workflow 調整（`.forgejo/workflows/build.yml`）

- 觸發補上 build script 路徑：`paths: [ "Dockerfile", ".forgejo/scripts/build_and_push.sh" ]`。
- `runs-on: redlib`（host label）不變。
- 兩平台 build/push/merge 都在 `build_and_push.sh` 內 sequential 完成。
- 磁碟紀律（12 機 30GB）：逐檔 prune，只留 BuildKit cargo cache（Tier 2）。

## 9. 驗證（上線前必做）

1. **amd64（若走 B1）**：容器啟動、`/` 回 HTTP 200、`readelf -d` 無 dynamic section。
2. **arm64**：`readelf -h` 確認 machine 為 AArch64；容器內可啟動。
3. **codeberg 多平台 manifest（重點待驗證）**：upstream 推 quay.io 全支援，
   **codeberg 未驗證**。用 `docker buildx imagetools inspect codeberg.org/lawlietr/redlib:latest`
   確認列兩平台；並實際在不同 arch 拉一次確認自動選對。（spec-compliant v2 registry，
   理論上 OK，但務必實測。）
4. **per-platform tag**：`docker pull …:amd64` 等確認解析到單檔。

## 10. 風險 / 待辦
- [x] **runner 工具鏈（script 層）**：`CXX_*`/`AR_*` 已補進 script（commit `fc555ee`）。
- [ ] **擴建 runner Dockerfile 安裝工具鏈**（`apk add` cross-compiler + rustup + clang）
  → 重建 runner 容器 → 驗證 daemon 能起 + 能原生交叉編譯兩 target —— P0 上線前最後一步 infra。
- [ ] **codeberg 多平台 manifest 實測驗證**（第 9.3 項）—— reliability 關鍵。
- [x] **amd64 libc 子決策 B1/B2**（第 4 項）—— 已定案 B1（兩檔統一 musl）。
- [ ] 12 機 30GB 在「兩檔同時暫存」時的峰值（Plan B sequential 可避；Plan A 需逐檔 push/prune）。
- [x] **GitHub Actions（`.github/workflows/build.yml`，ghcr.io 備援）已同步兩架構**（2026-10-21）：
      不再「暫緩」。改走**原生 arm64 hosted runner**（`ubuntu-24.04-arm`，public repo 免費 GA），
      不用 QEMU、不用交叉工具鏈；四個 tag 與 codeberg 版對齊（`latest`/`<git-sha>`/`amd64`/`arm64`）。
      ⚠ 这条路產的是 **glibc 靜態** binary（本檔的 Dockerfile 的 `+crt-static`），不是本檔描述的 musl 產物；
      見 `design/github-actions-workflow.md` §4/§5。

## 11. 與 upstream 差異

- upstream：在 GitHub Actions 編三 target → 發 GitHub release tarball → Dockerfile
  只 `curl` 下載打包（`main-docker.yml` + `build-artifacts.yaml`）。
- 我們：在**12 runner 原生交叉編譯**（無 QEMU、快）→ 直接打包推 codeberg。
  編譯位置與推送目標不同，target 與 musl 路線一致。
