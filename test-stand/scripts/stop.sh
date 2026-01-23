#!/bin/bash
# Остановка всех сервисов

SERVER="wogulis@192.168.1.5"

echo "🛑 Остановка всех сервисов..."

ssh $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml down"

echo "✅ Все сервисы остановлены"
