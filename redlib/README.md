# Redlib - Reddit 替代方案

Redlib 是一個輕量級的 Reddit 替代方案，專注於隱私和速度。

## 快速開始

### 使用 Docker Compose（推薦）

```bash
cd redlib
docker compose up -d
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
- 健康檢查會定期確認服務狀態

## 故障排除

### 建置失敗
- 檢查 Rust 和 Alpine 版本是否相容
- 確保網路連線正常

### 容器無法啟動
- 檢查端口 8080 是否被佔用
- 查看容器日誌：`docker logs redlib`

### 健康檢查失敗
- 確認網路連線
- 驗證端口綁定

## 專案資訊

- 原始碼倉庫：https://github.com/chowder/redlib
- 這個專案使用 Docker 進行容器化部署
