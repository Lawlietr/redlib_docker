# 多平台建置（amd64 + arm64 + armv7）— 實施要領

> 優先級 **P0**。本檔記錄「怎麼做」；工作進度見 `TODO.md`。
> 機敏資訊（`CODEBERG_PAT`）只放在 repo secret，不寫入本檔。

## 1. 目標

把現行**單一 amd64** 映像改為**三平台**，並用一份 `latest` manifest list 讓
`docker pull` 自動偵測架構：

- `linux/amd64`     ← `x86_64-unknown-linux-musl`
- `linux/arm64`     ← `aarch64-unknown-linux-musl`（樹莓派 3/4 64-bit）
- `linux/arm/v7`    ← `armv7-unknown-linux-musleabihf`（樹莓派 32-bit）

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
  三檔都 push 後：
    docker buildx imagetools create -t img:latest -t img:<sha> \
        img:amd64 img:arm64 img:armv7             # 合併成 manifest list
    docker push img:latest img:<sha>              # 推 manifest
```

為什麼不用 buildx `--platform all --push`（Plan A）：
- x86_64 機上 arm64/armv7 會跑 **QEMU 模擬**，armv7 尤其慢（可能 30–60 分）。
- `--platform all` 一次留三張暫存映像，**峰值碟可能衝破 30GB**。Plan B 逐檔
  build/push/prune 把峰值壓在單個 build，30GB 很穩。

## 4. target / libc 子決策（待確認）

- **B1（建議）：三檔統一 musl 靜態。** musl target 的 `+crt-static` 是 Rust 預設，
  不用手搓靜態 flag。match upstream、一套 flag、最乾淨。**會改 amd64 的編譯方法
  （glibc→musl）**，但 redlib 無 glibc 專屬需求，風險低，改完重測即可。
- **B2（對 amd64 零風險）：amd64 維持現行 glibc 靜態，只加 arm64/armv7 用 musl。**
  amd64 完全不動。代價：兩套 libc、較複雜、amd64 與 arm 無法共用編譯管線。

> **待 user 拍板 B1 / B2。** 未定前兩條路都記在此。

## 5. 工具鏈（12 機，x86_64 host）

交叉編譯需要的套件（裝在 builder 層 = 暫存，build 完 prune 清掉）：

```
gcc-aarch64-linux-gnu      # arm64 的 C 編譯器（boring-sys2 編 BoringSSL 用）
gcc-arm-linux-gnueabihf    # armv7 的 C 編譯器
musl-tools                 # musl libc（rustup 的 musl target 已內建 static libc）
clang libclang-dev         # bindgen（dlopen libclang，host glibc 正常）
cmake perl pkg-config git  # build deps
```

rust target（`rustup target add` 三個）：
```
x86_64-unknown-linux-musl
aarch64-unknown-linux-musl
armv7-unknown-linux-musleabihf
```

編譯指令（upstream 實測有效的寫法，env 只設 linker/CC）：
```bash
export CC_aarch64_unknown_linux_musl=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc
export CC_armv7_unknown_linux_musleabihf=arm-linux-gnueabihf-gcc
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-linux-gnueabihf-gcc

cargo build --release --locked --target x86_64-unknown-linux-musl
cargo build --release --locked --target aarch64-unknown-linux-musl
cargo build --release --locked --target armv7-unknown-linux-musleabihf
```

## 6. 打包：Dockerfile.pack（薄打包，不編譯）

每個 arch 的 binary 已預先編好，Dockerfile.pack 只負責包进 `scratch`：

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
| `latest` | manifest list（三平台） | 主用，`docker pull` 自動偵測架構 |
| `<version>` / `<git-sha>` | manifest list | 固定可重現的 pin |
| `amd64` / `arm64` / `armv7` | 單檔 | 明確 pull / 除錯 |

`latest` 與各平台 tag 並存。用 `imagetools create` 一次產出 `latest` + `<sha>`：
```bash
docker buildx imagetools create \
  -t "${IMAGE}:latest" -t "${IMAGE}:${GIT_SHA}" \
  "${IMAGE}:amd64" "${IMAGE}:arm64" "${IMAGE}:armv7"
```

## 8. workflow 調整（`.forgejo/workflows/build.yml`）

- 觸發補上 build script 路徑：`paths: [ "Dockerfile", ".forgejo/scripts/build_and_push.sh" ]`。
- `runs-on: redlib`（host label）不變。
- 三平台 build/push/merge 都在 `build_and_push.sh` 內 sequential 完成。
- 磁碟紀律（12 機 30GB）：逐檔 prune，只留 BuildKit cargo cache（Tier 2）。

## 9. 驗證（上線前必做）

1. **amd64（若走 B1）**：容器啟動、`/` 回 HTTP 200、`readelf -d` 無 dynamic section。
2. **arm64 / armv7**：`readelf -h` 確認 machine 為 AArch64 / ARM；容器內可啟動。
3. **codeberg 多平台 manifest（重點待驗證）**：upstream 推 quay.io 全支援，
   **codeberg 未驗證**。用 `docker buildx imagetools inspect codeberg.org/lawlietr/redlib:latest`
   確認列三平台；並實際在不同 arch 拉一次確認自動選對。（spec-compliant v2 registry，
   理論上 OK，但務必實測。）
4. **per-platform tag**：`docker pull …:amd64` 等確認解析到單檔。

## 10. 風險 / 待辦

- [ ] **codeberg 多平台 manifest 實測驗證**（第 9.3 項）—— reliability 關鍵。
- [ ] **amd64 libc 子決策 B1/B2**（第 4 項）—— 定案前不改碼。
- [ ] 12 機 30GB 在「三檔同時暂存」時的峰值（Plan B sequential 可避；Plan A 需逐檔 push/prune）。
- [ ] GitHub Actions（`.github/workflows/build.yml`，ghcr.io 備援）目前**暫緩**，
      待有 GitHub repo 再同步三平台（見 `design/github-actions-workflow.md`）。

## 11. 與 upstream 差異

- upstream：在 GitHub Actions 編三 target → 發 GitHub release tarball → Dockerfile
  只 `curl` 下載打包（`main-docker.yml` + `build-artifacts.yaml`）。
- 我們：在**本地 runner 原生交叉編譯**（無 QEMU、快）→ 直接打包推 codeberg。
  編譯位置與推送目標不同，target 與 musl 路線一致。
