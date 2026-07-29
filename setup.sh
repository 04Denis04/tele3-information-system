#!/bin/bash

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

APP_DIR="/opt/tele3"
DB_NAME="tele3"
DB_USER_APP="tele3_app"
DB_PASS_APP="${DB_PASS_APP:-change-me-before-running}"
export DB_PASS_APP
FLASK_PORT=5000

if [ "$DB_PASS_APP" = "change-me-before-running" ]; then
    error "Перед запуском задайте переменную DB_PASS_APP"
fi

info "Установка системных пакетов..."
sudo apt-get update -q
sudo apt-get install -y python3 python3-pip python3-venv \
    postgresql postgresql-contrib libpq-dev

info "Настройка PostgreSQL..."
sudo systemctl enable postgresql
sudo systemctl start postgresql

sudo -u postgres psql << 'PSQL'
SELECT 'CREATE DATABASE tele3 ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='tele3') \gexec
PSQL

info "Применение схемы БД..."
SCHEMA_FILE="$(dirname "$0")/tele3_database.sql"
[ -f "$SCHEMA_FILE" ] || error "Файл tele3_database.sql не найден. Добавьте схему БД перед запуском setup.sh."
sudo -u postgres psql -d tele3 -f "$SCHEMA_FILE"
sudo -u postgres psql -v app_password="$DB_PASS_APP" -d tele3 <<'PSQL'
SELECT format('ALTER ROLE tele3_app PASSWORD %L', :'app_password') \gexec
PSQL

info "Копирование приложения в $APP_DIR..."
sudo mkdir -p "$APP_DIR"
sudo cp -r "$(dirname "$0")/." "$APP_DIR/"
sudo chown -R "$USER":"$USER" "$APP_DIR"

info "Создание виртуального окружения Python..."
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip -q
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" -q

info "Создание systemd-сервиса..."
sudo tee /etc/systemd/system/tele3.service > /dev/null << EOF
[Unit]
Description=TELE3 Flask Information System
After=network.target postgresql.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment="DB_HOST=localhost"
Environment="DB_PORT=5432"
Environment="DB_NAME=tele3"
Environment="DB_USER=$DB_USER_APP"
Environment="DB_PASSWORD=$DB_PASS_APP"
Environment="SECRET_KEY=$(openssl rand -hex 32)"
ExecStart=$APP_DIR/venv/bin/python3 run.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tele3
sudo systemctl start tele3

sleep 2
if systemctl is-active --quiet tele3; then
    IP=$(hostname -I | awk '{print $1}')
    info "ИС ТЕЛЕ 3 успешно запущена!"
    info "Адрес для клиентской VM: http://${IP}:${FLASK_PORT}"
else
    error "Сервис не запустился. Проверьте: sudo journalctl -u tele3 -n 30"
fi

info "Создание тестовых пользователей с реальными хешами..."
"$APP_DIR/venv/bin/python3" << 'PYEOF'
import os
import sys
sys.path.insert(0, '/opt/tele3')
from werkzeug.security import generate_password_hash
import psycopg2

conn = psycopg2.connect(dbname='tele3', user='tele3_app', password=os.environ['DB_PASS_APP'])
cur = conn.cursor()

users = [
    ('admin',        os.environ.get('ADMIN_PASSWORD', 'change-me-admin'), 'admin'),
    ('sec_admin',    os.environ.get('SECURITY_ADMIN_PASSWORD', 'change-me-security'), 'security_admin'),
    ('support1',     os.environ.get('SUPPORT_PASSWORD', 'change-me-support'), 'support'),
    ('billing1',     os.environ.get('BILLING_PASSWORD', 'change-me-billing'), 'billing_operator'),
    ('user_ivanov',  os.environ.get('SUBSCRIBER_PASSWORD', 'change-me-subscriber'), 'subscriber'),
]
for username, password, role in users:
    ph = generate_password_hash(password)
    cur.execute("""
        UPDATE tele3.users SET password_hash = %s WHERE username = %s
    """, (ph, username))
    print(f"  Пароль обновлён для пользователя: {username}")

conn.commit()
cur.close()
conn.close()
print("Готово!")
PYEOF

info "Применение миграции tickets/security_log..."
sudo -u postgres psql -d tele3 -f "$(dirname "$0")/migrate_tickets.sql" 2>/dev/null || true
info "Миграция применена."
