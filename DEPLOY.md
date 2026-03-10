# DEPLOY - finance-suite

Tài liệu này mô tả cách chạy **finance-api** và **finance-bot** ở môi trường dev và production (systemd). Mục tiêu: **không commit secrets**; secrets phải nằm trong file riêng và/hoặc dạng `*_FILE`.

> Giả định layout deploy (khuyến nghị):
>
> - Source code: `/opt/finance-suite` (clone repo vào đây)
> - Venv theo từng service:
>   - API: `/opt/finance-suite/finance-api/.venv`
>   - Bot: `/opt/finance-suite/finance-bot/.venv`
> - Env files (secrets):
>   - `/etc/finance/finance-api.env`
>   - `/etc/finance/finance-bot.env`
> - Secret files:
>   - DB password: `/etc/finance/secrets/finance_db_password`
>   - JWT secret: `/etc/finance/secrets/jwt_secret`

---

## 1) Cấu hình ENV (API)

### Các biến môi trường chính
API đọc cấu hình từ environment (xem `finance-api/finance_api/app.py`). Danh sách:

- `FINANCE_DB_HOST` (default `127.0.0.1`)
- `FINANCE_DB_PORT` (default `5432`)
- `FINANCE_DB_NAME` (default `finance`)
- `FINANCE_DB_USER` (default `finance_user`)
- `FINANCE_DB_PASSWORD_FILE` **(khuyến nghị)**: đường dẫn file chứa password DB
  - fallback (không khuyến nghị): `FINANCE_DB_PASSWORD`

JWT:
- `JWT_SECRET_FILE` **(khuyến nghị)**: file chứa JWT secret
  - fallback: `JWT_SECRET`
- `JWT_ALG` (default `HS256`)
- `JWT_EXPIRE_DAYS` (default `14`)

Auth admin:
- `ADMIN_USERNAME` (default `huy`)
- `ADMIN_PASSWORD_BCRYPT`: bcrypt hash của mật khẩu admin (không phải plaintext)

Ingest:
- `INGEST_SHARED_SECRET`: secret dùng chung giữa bot và API (header `X-Ingest-Secret`)

### Ví dụ file `/etc/finance/finance-api.env`
```bash
# DB
FINANCE_DB_HOST=127.0.0.1
FINANCE_DB_PORT=5432
FINANCE_DB_NAME=finance
FINANCE_DB_USER=finance_user
FINANCE_DB_PASSWORD_FILE=/etc/finance/secrets/finance_db_password

# JWT
JWT_SECRET_FILE=/etc/finance/secrets/jwt_secret
JWT_ALG=HS256
JWT_EXPIRE_DAYS=14

# Admin
ADMIN_USERNAME=huy
ADMIN_PASSWORD_BCRYPT=$2b$12$...   # tạo bằng passlib/bcrypt

# Bot ingest
INGEST_SHARED_SECRET=...            # chuỗi mạnh, không lộ
```

---

## 2) Cấu hình ENV (Bot)

Bot đọc từ env (xem `finance-bot/bot.py`):

- `BOT_TOKEN`: Telegram bot token (**bắt buộc**) 
- `FINANCE_API_URL` (default `http://127.0.0.1:8088`) 
- `INGEST_SHARED_SECRET` (**bắt buộc** nếu API bật ingest)

### Ví dụ file `/etc/finance/finance-bot.env`
```bash
BOT_TOKEN=123456:ABCDEF...
FINANCE_API_URL=http://127.0.0.1:8088
INGEST_SHARED_SECRET=...
```

---

## 3) Chạy DEV (local)

### 3.1) Postgres
Tối thiểu cần Postgres chạy local. (Nếu chưa có schema) apply SQL:

```bash
psql -h 127.0.0.1 -U finance_user -d finance -f finance-api/sql/001_create_transactions_inbox.sql
```

### 3.2) Finance API
```bash
cd finance-api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# tạo env local (không commit)
cp .env.example .env
# sửa .env cho đúng máy bạn

set -a
source .env
set +a

uvicorn finance_api.app:app --host 127.0.0.1 --port 8088 --reload
```

Healthcheck:
```bash
curl -fsS http://127.0.0.1:8088/healthz
```

### 3.3) Finance Bot
```bash
cd finance-bot
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export BOT_TOKEN=...
export FINANCE_API_URL=http://127.0.0.1:8088
export INGEST_SHARED_SECRET=...

python bot.py
```

---

## 4) Chạy PRODUCTION với systemd

### 4.1) Tạo user + thư mục chuẩn
```bash
sudo useradd --system --create-home --home /var/lib/finance --shell /usr/sbin/nologin finance || true

sudo mkdir -p /opt/finance-suite /etc/finance/secrets /var/log/finance-api /var/log/finance-bot /var/lib/finance-api /var/lib/finance-bot
sudo chown -R finance:finance /var/log/finance-api /var/log/finance-bot /var/lib/finance-api /var/lib/finance-bot

sudo chown -R root:finance /etc/finance
sudo chmod 750 /etc/finance /etc/finance/secrets
```

### 4.2) Deploy source + venv
```bash
# clone/copy repo vào /opt/finance-suite
sudo rsync -a --delete /mnt/toshiba/projects/finance-suite/ /opt/finance-suite/
sudo chown -R finance:finance /opt/finance-suite

# tạo venv + cài deps
sudo -u finance bash -lc 'cd /opt/finance-suite/finance-api && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt'
sudo -u finance bash -lc 'cd /opt/finance-suite/finance-bot && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt'
```

### 4.3) Tạo env files + secret files
```bash
# env files
sudo install -m 640 -o root -g finance /dev/null /etc/finance/finance-api.env
sudo install -m 640 -o root -g finance /dev/null /etc/finance/finance-bot.env

# secrets
sudo install -m 640 -o root -g finance /dev/null /etc/finance/secrets/finance_db_password
sudo install -m 640 -o root -g finance /dev/null /etc/finance/secrets/jwt_secret

# edit nội dung
sudo nano /etc/finance/finance-api.env
sudo nano /etc/finance/finance-bot.env
sudo nano /etc/finance/secrets/finance_db_password
sudo nano /etc/finance/secrets/jwt_secret
```

> Lưu ý: API đang hỗ trợ `*_FILE` cho DB password & JWT secret (đúng yêu cầu “secrets không commit”).

### 4.4) Cài systemd units
Trong repo đã có template:
- `deploy/systemd/finance-api.service`
- `deploy/systemd/finance-bot.service`

Cài đặt:
```bash
sudo cp /opt/finance-suite/deploy/systemd/finance-api.service /etc/systemd/system/finance-api.service
sudo cp /opt/finance-suite/deploy/systemd/finance-bot.service /etc/systemd/system/finance-bot.service

sudo systemctl daemon-reload
sudo systemctl enable --now finance-api
sudo systemctl enable --now finance-bot
```

### 4.5) Restart / logs / status
```bash
sudo systemctl restart finance-api
sudo systemctl restart finance-bot

sudo systemctl status finance-api --no-pager
sudo systemctl status finance-bot --no-pager

# logs
sudo journalctl -u finance-api -f
sudo journalctl -u finance-bot -f
```

### 4.6) Healthcheck
- API: `GET /healthz`
```bash
curl -fsS http://127.0.0.1:8088/healthz
```

> Nếu expose ra ngoài qua Nginx/Caddy, nên giữ API bind `127.0.0.1` và reverse-proxy.

---

## 5) Backup / Restore DB (cơ bản)

### Backup
```bash
# backup full database
pg_dump -h 127.0.0.1 -U finance_user -d finance -Fc -f finance_$(date +%F).dump
```

### Restore
```bash
# restore vào DB trống (cẩn thận overwrite)
pg_restore -h 127.0.0.1 -U finance_user -d finance --clean --if-exists finance_YYYY-MM-DD.dump
```

Khuyến nghị:
- lưu backup vào nơi có snapshot (VD: `/var/backups/finance/`) và set quyền truy cập chặt.
- nếu DB nằm trên VPS: nên dùng cron + rotate theo ngày/tuần.

---

## 6) Các điểm cần chốt với Sếp Huy (để deploy “đúng bài”)

1. **VPS/host target**: IP/hostname cụ thể? (và OS distro)
2. **DB đặt ở đâu**: cùng máy hay managed Postgres? (host/port/user/dbname)
3. **Expose API ra ngoài không**:
   - nếu có: dùng Nginx/Caddy? domain nào? HTTPS? 
   - port public dự kiến (và firewall)
4. **Bot chạy polling hay webhook**:
   - hiện tại code chạy polling; nếu muốn webhook cần thêm endpoint + reverse proxy + TLS.
5. **Đường dẫn chuẩn khi deploy**: giữ `/opt/finance-suite` hay path khác.
6. **Cơ chế rotate logs**: hiện dùng journald; có cần log file riêng không.

