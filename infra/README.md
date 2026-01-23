# 🛠️ Инфраструктура TrackerGPS

Централизованное управление инфраструктурой и сервисами.

## 📁 Структура

```
infra/
├── scripts/              # Bash скрипты для управления
│   ├── init-all.sh           # Инициализация всей системы
│   ├── start-dev.sh          # Запуск dev окружения в tmux
│   ├── stop-all.sh           # Остановка всех сервисов
│   ├── create-kafka-topics.sh # Создание Kafka топиков
│   ├── init-timescaledb.sh   # Инициализация TimescaleDB
│   └── health-check.sh       # Проверка здоровья сервисов
│
├── databases/           # SQL скрипты для инициализации БД
│   └── timescaledb-init.sql  # Схема TimescaleDB
│
├── docker/              # Dockerfiles для базовых образов
│   └── (будут добавлены)
│
├── kubernetes/          # K8s манифесты для production
│   └── (будут добавлены)
│
└── monitoring/          # Конфигурации Prometheus/Grafana
    └── (будут добавлены)
```

## 🚀 Быстрый старт

### 1. Инициализация всей системы

```bash
./infra/scripts/init-all.sh
```

**Что делает:**
- ✅ Проверяет Docker и Docker Compose
- ✅ Инициализирует git submodules
- ✅ Создаёт директории для данных
- ✅ Запускает инфраструктуру (Kafka, Redis, TimescaleDB)
- ✅ Создаёт Kafka топики (12 партиций для gps-events)
- ✅ Инициализирует TimescaleDB (таблицы, индексы, hypertables)
- ✅ Компилирует все сервисы (SBT)

### 2. Запуск dev окружения

```bash
./infra/scripts/start-dev.sh
```

**Запускает tmux сессию с 6 окнами:**
- **infra** - логи Docker Compose
- **conn-mgr** - Connection Manager (TCP сервер)
- **history** - History Writer (Kafka → TimescaleDB)
- **device-mgr** - Device Manager (REST API)
- **kafka-debug** - Kafka Console Consumer
- **redis-debug** - Redis CLI

**Навигация в tmux:**
```
Ctrl+b, n      - следующее окно
Ctrl+b, p      - предыдущее окно
Ctrl+b, 0-6    - переключиться на окно N
Ctrl+b, d      - отключиться (сервисы продолжат работать)
```

### 3. Проверка здоровья

```bash
./infra/scripts/health-check.sh
```

**Проверяет:**
- Redis (localhost:6379)
- Kafka (localhost:9092)
- TimescaleDB (localhost:5432)
- Prometheus (http://localhost:9090)
- Grafana (http://localhost:3000)
- Микросервисы (если запущены)

### 4. Остановка

```bash
./infra/scripts/stop-all.sh
```

Останавливает все сервисы и Docker контейнеры.

## 📊 Kafka топики

| Топик | Партиции | Retention | Описание |
|-------|----------|-----------|----------|
| `gps-events` | 12 | 7 дней | GPS данные с устройств |
| `device-commands` | 6 | 7 дней | Команды на устройства |
| `geozone-events` | 6 | 7 дней | События геозон |
| `notifications` | 3 | 7 дней | Уведомления |
| `device-status` | 6 | 7 дней | Статусы устройств |

**Партиционирование:**
- GPS события: hash(vehicleId) % 12 для гарантии порядка
- Команды: hash(imei) % 6

## 🗄️ TimescaleDB схема

### Hypertables (партиционированные по времени)

- **gps_positions** - GPS позиции (chunk: 7 дней)
  - Автоматическое сжатие через 7 дней
  - Удаление через 1 год
  - PostGIS индекс для геопоиска

- **device_commands** - история команд (chunk: 30 дней)
  - Удаление через 90 дней

- **geozone_events** - события геозон (chunk: 30 дней)
  - Удаление через 6 месяцев

### Обычные таблицы

- **devices** - устройства
- **vehicles** - транспортные средства
- **geozones** - геозоны (PostGIS полигоны)

### Continuous Aggregates

- **daily_device_stats** - суточная статистика (обновление каждый час)

## 🔌 Порты сервисов

| Сервис | Порт | Описание |
|--------|------|----------|
| Redis | 6379 | Кэш позиций, очереди команд |
| Kafka | 9092 | Event streaming |
| ZooKeeper | 2181 | Kafka координация |
| TimescaleDB | 5432 | Хранение GPS истории |
| Prometheus | 9090 | Сбор метрик |
| Grafana | 3000 | Дашборды (admin/admin) |
| Connection Manager | 5001-5004 | TCP серверы для GPS протоколов |
| Device Manager | 8081 | REST API |
| History Writer | 8082 | Health endpoint |

## 🐳 Docker Compose

Основной `docker-compose.yml` в корне репозитория содержит:

- **redis** - Redis 7
- **zookeeper** - ZooKeeper для Kafka
- **kafka** - Apache Kafka 3.6
- **timescaledb** - PostgreSQL + TimescaleDB + PostGIS
- **prometheus** - Prometheus для метрик
- **grafana** - Grafana для визуализации

## 📝 Полезные команды

### Kafka

```bash
# Список топиков
docker exec wayrecall-kafka kafka-topics.sh --list --bootstrap-server localhost:9092

# Читать сообщения из топика
docker exec -it wayrecall-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic gps-events \
  --from-beginning

# Отправить тестовое сообщение
echo "test-key:test-value" | docker exec -i wayrecall-kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic gps-events \
  --property "parse.key=true" \
  --property "key.separator=:"
```

### Redis

```bash
# Подключиться к Redis
docker exec -it wayrecall-redis redis-cli

# Посмотреть все ключи
docker exec wayrecall-redis redis-cli KEYS '*'

# Получить последнюю позицию
docker exec wayrecall-redis redis-cli GET "last_position:123456789012345"
```

### TimescaleDB

```bash
# Подключиться к БД
docker exec -it wayrecall-timescaledb psql -U tracker -d trackerdb

# Количество GPS позиций
docker exec wayrecall-timescaledb psql -U tracker -d trackerdb \
  -c "SELECT COUNT(*) FROM gps_positions;"

# Последние 10 позиций
docker exec wayrecall-timescaledb psql -U tracker -d trackerdb \
  -c "SELECT time, imei, latitude, longitude, speed FROM gps_positions ORDER BY time DESC LIMIT 10;"
```

## 🔧 Разработка

### Добавить новый скрипт

1. Создать `.sh` файл в `infra/scripts/`
2. Сделать исполняемым: `chmod +x infra/scripts/new-script.sh`
3. Добавить shebang: `#!/bin/bash`
4. Использовать `set -e` для остановки при ошибках

### Обновить схему БД

1. Отредактировать `infra/databases/timescaledb-init.sql`
2. Пересоздать БД:
   ```bash
   docker-compose down timescaledb
   docker volume rm wayrecall-tracker-system-template_timescaledb-data
   docker-compose up -d timescaledb
   ./infra/scripts/init-timescaledb.sh
   ```

### Добавить Kafka топик

Отредактировать `infra/scripts/create-kafka-topics.sh` и выполнить:
```bash
./infra/scripts/create-kafka-topics.sh
```

## 🚨 Troubleshooting

### Kafka не стартует

```bash
# Проверить логи
docker-compose logs kafka

# Пересоздать
docker-compose down kafka zookeeper
docker volume rm wayrecall-tracker-system-template_kafka-data
docker-compose up -d kafka
```

### TimescaleDB не инициализируется

```bash
# Проверить что контейнер запущен
docker ps | grep timescaledb

# Проверить логи
docker-compose logs timescaledb

# Ручная инициализация
docker exec -i wayrecall-timescaledb psql -U tracker -d trackerdb < infra/databases/timescaledb-init.sql
```

### Порт занят

```bash
# Найти процесс использующий порт
sudo lsof -i :6379

# Остановить
kill -9 <PID>
```

## 📚 Дополнительные ресурсы

- [TimescaleDB Documentation](https://docs.timescale.com/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Redis Commands](https://redis.io/commands/)
- [PostGIS Documentation](https://postgis.net/docs/)
