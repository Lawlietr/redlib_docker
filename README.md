# Redlib Docker

輕量級 Reddit 替代方案，透過 Docker 部署。

**已合併 PR#506、PR#509**
- PR#506: https://github.com/redlib-org/redlib/pull/506
- PR#509: https://github.com/redlib-org/redlib/pull/509

## 快速開始

```bash
docker build -f redlib/Dockerfile -t redlib .
docker run -p 8080:8080 -d --name redlib redlib
```

## 環境變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `PORT` | 8080 | 伺服器端口 |
| `DOMAIN` | localhost | 域名設定 |
| `REDIS_URL` | - | Redis 連線 (選填) |

## 自定義建置

```bash
# 指定 Alpine 版本
docker build --build-arg ALPINE_VERSION=3.22 -f redlib/Dockerfile -t redlib .

# 指定 Redlib 分支
docker build --build-arg REDLIB_BRANCH=main -f redlib/Dockerfile -t redlib .
```

## 專案資訊

- 原始碼：https://github.com/redlib-org/redlib
- Docker 個人實作，非官方專案