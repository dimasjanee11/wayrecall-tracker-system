#!/bin/bash
# Проверка здоровья всех сервисов
# Использование: ./infra/scripts/health-check.sh

set -e

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🏥 Проверка здоровья сервисов..."
echo ""

check_service() {
    local name=$1
    local host=$2
    local port=$3
    
    if nc -z $host $port 2>/dev/null; then
        echo -e "${GREEN}✅ $name${NC} - доступен на $host:$port"
        return 0
    else
        echo -e "${RED}❌ $name${NC} - недоступен на $host:$port"
        return 1
    fi
}

check_http() {
    local name=$1
    local url=$2
    
    if curl -s -f $url > /dev/null; then
        echo -e "${GREEN}✅ $name${NC} - HTTP OK ($url)"
        return 0
    else
        echo -e "${RED}❌ $name${NC} - HTTP Failed ($url)"
        return 1
    fi
}

# Проверка базовых сервисов
echo "Инфраструктура:"
check_service "Redis" "localhost" 6379
check_service "Kafka" "localhost" 9092
check_service "TimescaleDB" "localhost" 5432
echo ""

# Проверка мониторинга
echo "Мониторинг:"
check_http "Prometheus" "http://localhost:9090/-/healthy"
check_http "Grafana" "http://localhost:3000/api/health"
echo ""

# Проверка микросервисов (если запущены)
echo "Микросервисы:"
check_service "Connection Manager" "localhost" 5001 || echo -e "${YELLOW}⚠️  Connection Manager не запущен${NC}"
check_http "Device Manager" "http://localhost:8081/health" || echo -e "${YELLOW}⚠️  Device Manager не запущен${NC}"
check_http "History Writer" "http://localhost:8082/health" || echo -e "${YELLOW}⚠️  History Writer не запущен${NC}"
echo ""

# Проверка Docker контейнеров
echo "Docker контейнеры:"
docker-compose ps

echo ""
echo "✅ Проверка завершена!"
