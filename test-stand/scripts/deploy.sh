#!/bin/bash
# Деплой TrackerGPS на сервер

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Конфигурация
SERVER="wogulis@192.168.1.5"
REMOTE_PATH="/home/wogulis/projects/wayrecall-tracker-system"
LOCAL_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  TrackerGPS Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Проверка .env файла
if [ ! -f "$LOCAL_PATH/test-stand/.env" ]; then
    echo -e "${YELLOW}⚠️  Файл .env не найден!${NC}"
    echo -e "${YELLOW}   Создайте его из .env.example:${NC}"
    echo -e "   ${BLUE}cp test-stand/.env.example test-stand/.env${NC}"
    echo -e "   ${BLUE}nano test-stand/.env${NC}"
    exit 1
fi

echo -e "${GREEN}[1/5]${NC} Синхронизация файлов на сервер..."
rsync -avz --delete \
    --exclude '.git' \
    --exclude 'target' \
    --exclude '.bsp' \
    --exclude '.metals' \
    --exclude '.idea' \
    --exclude 'node_modules' \
    "$LOCAL_PATH/" "$SERVER:$REMOTE_PATH/"

echo ""
echo -e "${GREEN}[2/5]${NC} Остановка старых контейнеров..."
ssh $SERVER "cd $REMOTE_PATH && docker compose -f test-stand/docker-compose.prod.yml down" || true

echo ""
echo -e "${GREEN}[3/5]${NC} Запуск инфраструктуры..."
ssh $SERVER << 'ENDSSH'
cd /home/wogulis/projects/wayrecall-tracker-system

# Загрузить переменные окружения
export $(cat test-stand/.env | grep -v '^#' | xargs)

# Запустить контейнеры
docker compose -f test-stand/docker-compose.prod.yml up -d

# Дождаться готовности
echo "⏳ Ожидание готовности сервисов..."
sleep 30

# Проверить статус
docker compose -f test-stand/docker-compose.prod.yml ps
ENDSSH

echo ""
echo -e "${GREEN}[4/5]${NC} Инициализация Kafka топиков..."
ssh $SERVER "cd $REMOTE_PATH && bash infra/scripts/create-kafka-topics.sh" || echo -e "${YELLOW}⚠️  Kafka топики уже существуют${NC}"

echo ""
echo -e "${GREEN}[5/5]${NC} Инициализация TimescaleDB..."
ssh $SERVER "cd $REMOTE_PATH && bash infra/scripts/init-timescaledb.sh" || echo -e "${YELLOW}⚠️  TimescaleDB уже инициализирована${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Развертывание завершено!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Доступные сервисы:${NC}"
echo -e "  🗄️  PostgreSQL:  192.168.1.5:5432"
echo -e "  🔴 Redis:        192.168.1.5:6379"
echo -e "  📨 Kafka:        192.168.1.5:9092"
echo -e "  📊 Prometheus:   http://192.168.1.5:9090"
echo -e "  📈 Grafana:      http://192.168.1.5:3000"
echo ""
echo -e "${BLUE}Полезные команды:${NC}"
echo -e "  Статус:    ${GREEN}./test-stand/scripts/status.sh${NC}"
echo -e "  Логи:      ${GREEN}./test-stand/scripts/logs.sh${NC}"
echo -e "  Backup:    ${GREEN}./test-stand/scripts/backup.sh${NC}"
