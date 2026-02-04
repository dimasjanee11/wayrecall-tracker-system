#!/bin/bash
# Создание Kafka топиков для TrackerGPS
# Использование: ./infra/scripts/create-kafka-topics.sh

set -e

echo "📊 Создание Kafka топиков..."

# Переменные
KAFKA_CONTAINER="tracker-kafka"
PARTITIONS=12
REPLICATION_FACTOR=1

# Функция создания топика
create_topic() {
    local topic=$1
    local partitions=${2:-$PARTITIONS}
    
    echo "  Создание топика: $topic (partitions=$partitions)..."
    
    docker exec $KAFKA_CONTAINER kafka-topics.sh \
        --create \
        --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic $topic \
        --partitions $partitions \
        --replication-factor $REPLICATION_FACTOR \
        --config retention.ms=604800000 \
        --config compression.type=lz4
}

# Основные топики
create_topic "gps-events" 12           # GPS данные с устройств (12 партиций для 10K устройств)
create_topic "device-commands" 6        # Команды на устройства
create_topic "geozone-events" 6         # События геозон (въезд/выезд)
create_topic "notifications" 3          # Уведомления пользователям
create_topic "device-status" 6          # Статусы устройств (online/offline)
create_topic "unknown-devices" 3        # Попытки подключения неизвестных устройств
create_topic "gps-events-unverified" 6  # DLQ для точек без проверки (Redis недоступен)

echo ""
echo "✅ Все топики созданы!"
echo ""
echo "Список топиков:"
docker exec $KAFKA_CONTAINER kafka-topics.sh \
    --list \
    --bootstrap-server localhost:9092
