#!/bin/bash
# Проверка статуса всех сервисов TrackerGPS

set -e

SERVER="wogulis@192.168.1.5"
REMOTE_PATH="/home/wogulis/projects/wayrecall-tracker-system"

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  TrackerGPS Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ssh $SERVER << 'ENDSSH'
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd /home/wogulis/projects/wayrecall-tracker-system

# Системные ресурсы
echo -e "${BLUE}💻 Системные ресурсы:${NC}"
echo "CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory:"
free -h | grep Mem | awk '{print "  Total: "$2" | Used: "$3" | Free: "$4" | Available: "$7}'
echo "RAID Disk:"
df -h /mnt/raid | tail -1 | awk '{print "  Size: "$2" | Used: "$3" ("$5") | Free: "$4}'
echo ""

# Docker контейнеры
echo -e "${BLUE}🐳 Docker контейнеры:${NC}"
docker compose -f test-stand/docker-compose.prod.yml ps

echo ""

# Использование ресурсов контейнерами
echo -e "${BLUE}📊 Использование ресурсов:${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep tracker

echo ""

# Health checks
echo -e "${BLUE}🏥 Health Checks:${NC}"

# Redis
if docker exec tracker-redis redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Redis${NC} - OK"
else
    echo -e "${RED}❌ Redis${NC} - DOWN"
fi

# Kafka
if docker exec tracker-kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Kafka${NC} - OK"
else
    echo -e "${RED}❌ Kafka${NC} - DOWN"
fi

# PostgreSQL
if docker exec tracker-timescaledb pg_isready -U tracker > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PostgreSQL${NC} - OK"
else
    echo -e "${RED}❌ PostgreSQL${NC} - DOWN"
fi

# Prometheus
if curl -sf http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Prometheus${NC} - OK"
else
    echo -e "${RED}❌ Prometheus${NC} - DOWN"
fi

# Grafana
if curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Grafana${NC} - OK"
else
    echo -e "${RED}❌ Grafana${NC} - DOWN"
fi

echo ""

# Kafka топики
echo -e "${BLUE}📨 Kafka топики:${NC}"
docker exec tracker-kafka kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null || echo -e "${YELLOW}⚠️  Не удалось получить список${NC}"

echo ""

# PostgreSQL статистика
echo -e "${BLUE}🗄️  PostgreSQL статистика:${NC}"
docker exec tracker-timescaledb psql -U tracker -d tracker -c "
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 5;
" 2>/dev/null || echo -e "${YELLOW}⚠️  База еще не инициализирована${NC}"

ENDSSH

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Status check complete${NC}"
echo -e "${GREEN}========================================${NC}"
