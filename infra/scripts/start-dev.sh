#!/bin/bash
# Запуск dev окружения в tmux с отдельными панелями для каждого сервиса
# Использование: ./infra/scripts/start-dev.sh

set -e

SESSION_NAME="wayrecall-dev"

# Проверка tmux
if ! command -v tmux &> /dev/null; then
    echo "❌ tmux не установлен. Установите: sudo apt install tmux"
    exit 1
fi

# Убить существующую сессию если есть
tmux kill-session -t $SESSION_NAME 2>/dev/null || true

echo "🚀 Запуск dev окружения в tmux..."
echo ""

# Создать новую сессию
tmux new-session -d -s $SESSION_NAME -n "infra"

# Окно 1: Инфраструктура (docker-compose logs)
tmux send-keys -t $SESSION_NAME:infra "cd $PWD && docker-compose logs -f" C-m

# Окно 2: Connection Manager
tmux new-window -t $SESSION_NAME -n "conn-mgr"
tmux send-keys -t $SESSION_NAME:conn-mgr "cd $PWD && sbt 'project connection-manager' run" C-m

# Окно 3: History Writer
tmux new-window -t $SESSION_NAME -n "history"
tmux send-keys -t $SESSION_NAME:history "cd $PWD && sbt 'project history-writer' run" C-m

# Окно 4: Device Manager
tmux new-window -t $SESSION_NAME -n "device-mgr"
tmux send-keys -t $SESSION_NAME:device-mgr "cd $PWD && sbt 'project device-manager' run" C-m

# Окно 5: Kafka Console Consumer (для отладки)
tmux new-window -t $SESSION_NAME -n "kafka-debug"
tmux send-keys -t $SESSION_NAME:kafka-debug "docker exec -it tracker-kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic gps-events --property print.key=true --property key.separator=':'" C-m

# Окно 6: Redis CLI (для отладки)
tmux new-window -t $SESSION_NAME -n "redis-debug"
tmux send-keys -t $SESSION_NAME:redis-debug "docker exec -it tracker-redis redis-cli" C-m

# Вернуться на первое окно
tmux select-window -t $SESSION_NAME:infra

echo "✅ Dev окружение запущено в tmux!"
echo ""
echo "Подключиться к сессии:"
echo "  tmux attach -t $SESSION_NAME"
echo ""
echo "Навигация в tmux:"
echo "  Ctrl+b, n    - следующее окно"
echo "  Ctrl+b, p    - предыдущее окно"
echo "  Ctrl+b, 0-6  - переключиться на окно N"
echo "  Ctrl+b, d    - отключиться от сессии (сервисы продолжат работать)"
echo ""
echo "Остановить все:"
echo "  tmux kill-session -t $SESSION_NAME"
echo ""

# Автоматически подключиться к сессии
tmux attach -t $SESSION_NAME
