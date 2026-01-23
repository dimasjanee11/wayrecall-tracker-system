#!/bin/bash
# Остановка всех сервисов
# Использование: ./infra/scripts/stop-all.sh

set -e

echo "🛑 Остановка всех сервисов..."
echo ""

# Остановить tmux сессию если запущена
if tmux has-session -t wayrecall-dev 2>/dev/null; then
    echo "Остановка dev сессии в tmux..."
    tmux kill-session -t wayrecall-dev
    echo "✅ Tmux сессия остановлена"
fi

# Остановить Docker Compose
echo "Остановка Docker контейнеров..."
docker-compose down

echo ""
echo "✅ Все сервисы остановлены!"
