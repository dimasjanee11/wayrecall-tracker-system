#!/bin/bash
# Инициализация TimescaleDB для TrackerGPS
# Использование: ./infra/scripts/init-timescaledb.sh

set -e

echo "🗄️  Инициализация TimescaleDB..."

# Переменные
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="trackerdb"
DB_USER="tracker"
DB_PASSWORD="tracker123"

# Ожидание готовности PostgreSQL
echo "⏳ Ожидание готовности TimescaleDB..."
until docker exec wayrecall-timescaledb pg_isready -U $DB_USER; do
  sleep 2
done

echo "✅ TimescaleDB готова к работе"
echo ""

# Выполнение SQL скрипта инициализации
echo "📝 Выполнение SQL скрипта инициализации..."
docker exec -i wayrecall-timescaledb psql -U $DB_USER -d $DB_NAME < infra/databases/timescaledb-init.sql

echo ""
echo "✅ TimescaleDB инициализирована!"
echo ""
echo "Подключение:"
echo "  Host:     $DB_HOST:$DB_PORT"
echo "  Database: $DB_NAME"
echo "  User:     $DB_USER"
