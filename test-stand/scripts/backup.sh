#!/bin/bash
# Создание backup всех данных

set -e

SERVER="wogulis@192.168.1.5"
BACKUP_DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="tracker_backup_${BACKUP_DATE}.tar.gz"

echo "🔄 Создание backup: $BACKUP_NAME"

ssh $SERVER << ENDSSH
set -e

BACKUP_DIR="/mnt/raid/backups"
BACKUP_DATE="$BACKUP_DATE"
BACKUP_NAME="$BACKUP_NAME"

mkdir -p \$BACKUP_DIR

echo "📦 Backup PostgreSQL..."
docker exec tracker-timescaledb pg_dump -U tracker tracker > \$BACKUP_DIR/postgres_\${BACKUP_DATE}.sql

echo "📦 Backup Redis..."
docker exec tracker-redis redis-cli SAVE
docker cp tracker-redis:/data/dump.rdb \$BACKUP_DIR/redis_\${BACKUP_DATE}.rdb

echo "📦 Архивирование..."
cd \$BACKUP_DIR
tar -czf \$BACKUP_NAME \
    postgres_\${BACKUP_DATE}.sql \
    redis_\${BACKUP_DATE}.rdb

# Удалить временные файлы
rm postgres_\${BACKUP_DATE}.sql redis_\${BACKUP_DATE}.rdb

echo "✅ Backup создан: \$BACKUP_DIR/\$BACKUP_NAME"
ls -lh \$BACKUP_DIR/\$BACKUP_NAME

# Удалить старые backup'ы (старше 30 дней)
find \$BACKUP_DIR -name "tracker_backup_*.tar.gz" -mtime +30 -delete
echo "🗑️  Старые backup'ы удалены"
ENDSSH

echo ""
echo "✅ Backup завершен!"
