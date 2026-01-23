#!/bin/bash
# Инициализация всей системы TrackerGPS
# Использование: ./infra/scripts/init-all.sh

set -e

echo "🚀 Инициализация wayrecall-tracker-system..."
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Проверка Docker
echo -e "${BLUE}[1/7]${NC} Проверка Docker..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Установите Docker: https://docs.docker.com/get-docker/"
    exit 1
fi
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose не установлен."
    exit 1
fi
echo -e "${GREEN}✅ Docker и Docker Compose установлены${NC}"
echo ""

# 2. Инициализация git submodules
echo -e "${BLUE}[2/7]${NC} Инициализация git submodules..."
git submodule update --init --recursive
echo -e "${GREEN}✅ Submodules инициализированы${NC}"
echo ""

# 3. Создание директорий для данных
echo -e "${BLUE}[3/7]${NC} Создание директорий для данных..."
mkdir -p infra/data/postgres
mkdir -p infra/data/redis
mkdir -p infra/data/kafka
mkdir -p infra/data/zookeeper
mkdir -p infra/data/prometheus
mkdir -p infra/data/grafana
echo -e "${GREEN}✅ Директории созданы${NC}"
echo ""

# 4. Запуск инфраструктуры (Kafka, Redis, PostgreSQL)
echo -e "${BLUE}[4/7]${NC} Запуск инфраструктуры (Kafka, Redis, TimescaleDB)..."
docker-compose up -d redis kafka zookeeper timescaledb
echo -e "${YELLOW}⏳ Ожидание готовности сервисов (30 сек)...${NC}"
sleep 30
echo -e "${GREEN}✅ Инфраструктура запущена${NC}"
echo ""

# 5. Создание Kafka топиков
echo -e "${BLUE}[5/7]${NC} Создание Kafka топиков..."
bash infra/scripts/create-kafka-topics.sh
echo -e "${GREEN}✅ Kafka топики созданы${NC}"
echo ""

# 6. Инициализация TimescaleDB
echo -e "${BLUE}[6/7]${NC} Инициализация TimescaleDB..."
bash infra/scripts/init-timescaledb.sh
echo -e "${GREEN}✅ TimescaleDB инициализирована${NC}"
echo ""

# 7. Компиляция всех сервисов
echo -e "${BLUE}[7/7]${NC} Компиляция всех сервисов..."
if command -v sbt &> /dev/null; then
    sbt compile
    echo -e "${GREEN}✅ Все сервисы скомпилированы${NC}"
else
    echo -e "${YELLOW}⚠️  SBT не установлен. Пропускаю компиляцию.${NC}"
fi
echo ""

echo -e "${GREEN}🎉 Инициализация завершена!${NC}"
echo ""
echo "Следующие шаги:"
echo "  1. Запустить все сервисы:    ./infra/scripts/start-dev.sh"
echo "  2. Проверить health:         ./infra/scripts/health-check.sh"
echo "  3. Просмотреть логи:         docker-compose logs -f"
echo ""
echo "Доступные сервисы:"
echo "  - Redis:        localhost:6379"
echo "  - Kafka:        localhost:9092"
echo "  - PostgreSQL:   localhost:5432"
echo "  - Prometheus:   http://localhost:9090"
echo "  - Grafana:      http://localhost:3000 (admin/admin)"
