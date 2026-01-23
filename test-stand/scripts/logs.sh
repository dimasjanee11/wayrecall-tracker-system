#!/bin/bash
# Просмотр логов сервисов

SERVER="wogulis@192.168.1.5"
SERVICE=${1:-all}
LINES=${2:-50}

if [ "$SERVICE" == "all" ]; then
    ssh $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml logs --tail=$LINES -f"
else
    ssh $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml logs --tail=$LINES -f $SERVICE"
fi
