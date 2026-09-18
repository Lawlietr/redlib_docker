# Redlib - Reddit 替代方案

Redlib 是一個輕量級的 Reddit 替代方案，專注於隱私和速度。

## 快速開始

預編譯映像（CI 自動推送）：`codeberg.org/lawlietr/redlib:latest`，
部署方式見 repo 根目錄 `README.md`。

本目錄的 `docker-compose.yaml` 用於**本地從原始碼建置**：

```bash
cd redlib
docker compose up -d --build
```

### 手動建置

```bash
# 建置鏡像
docker build -f Dockerfile -t redlib .

# 執行容器
docker run -p 8080:8080 -d --name redlib redlib
```

## 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `PORT` | 8080 | 伺服器端口 |
| `DOMAIN` | localhost | 域名設定 |

## 使用說明

- 啟動後可透過 http://localhost:8080 存取
- 容器預設會監聽在 8080 端口

## 故障排除

### 建置失敗
- 確保網路連線正常（build 過程會 clone upstream 與拉取 Rust 套件）
- boring-sys2（BoringSSL）需要 cmake + C 編譯器 + libclang，builder 映像已內建

### 容器無法啟動
- 檢查端口 8080 是否被佔用
- 查看容器日誌：`docker logs redlib`

## 專案資訊

- 原始碼倉庫：https://github.com/redlib-org/redlib
- 這個專案使用 Docker 進行容器化部署
