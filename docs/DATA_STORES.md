# 💾 Data Stores: Схемы хранилищ

> **Документ описывает:** TimescaleDB, PostgreSQL, Redis, Kafka  
> **Версия:** 3.0

---

## 📊 Расчёт объёмов хранения

### Входные данные
| Параметр | Значение |
|----------|----------|
| Количество трекеров | 10,000 |
| Точек/сек на трекер | 1 (движущиеся ~30%) |
| Размер GPS точки | ~200 bytes (JSON) |
| Рабочие часы | 24/7 |

### Потоки данных
| Поток | Расчёт | Объём/сек | Объём/день |
|-------|--------|-----------|------------|
| **gps-events** | 10K × 1 | ~2 MB/sec | ~170 GB |
| **gps-events-rules** | ~3K × 1 (30% с геозонами) | ~0.6 MB/sec | ~50 GB |

### TimescaleDB (со сжатием 15x)
| Период | Сырые | Сжатые | Retention |
|--------|-------|--------|-----------|
| 1 день | 170 GB | ~11 GB | ✅ |
| 7 дней | 1.2 TB | ~80 GB | Compression starts |
| 30 дней | 5.1 TB | ~340 GB | ✅ |
| 90 дней | 15.3 TB | **~1 TB** | Retention policy |

### Kafka
| Топик | Retention | Расчёт | Объём |
|-------|-----------|--------|-------|
| gps-events | 7 дней | 170 GB × 7 | ~1.2 TB |
| gps-events-rules | 7 дней | 50 GB × 7 | ~350 GB |
| gps-events-unverified | 7 дней | ~1 GB × 7 (1% fail rate) | ~7 GB |
| geozone-events | 30 дней | ~1 GB × 30 | ~30 GB |
| device-status | 7 дней | ~100 MB × 7 | ~700 MB |

**Итого Kafka:** ~1.6 TB (нормально для одного брокера)

### Redis
| Структура | Расчёт | Объём |
|-----------|--------|-------|
| device:{imei} × 10K | ~500 bytes × 10K | ~5 MB |
| pending_commands | ~1KB × 1K (avg) | ~1 MB |
| command_status | ~200 bytes × 10K | ~2 MB |

**Итого Redis:** ~10-50 MB (negligible)

---

## 📋 Обзор хранилищ

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA STORES OVERVIEW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        TimescaleDB + PostGIS                         │   │
│  │                                                                       │   │
│  │   • gps_points (hypertable) — GPS точки, ~11 GB/день (сжатые)       │   │
│  │   • sensor_data (hypertable) — Данные датчиков                      │   │
│  │   • geozones (PostGIS) — Геозоны с геометрией                       │   │
│  │   • geozone_events — События входа/выхода                           │   │
│  │   • trips — Поездки                                                 │   │
│  │   • device_daily_stats — Агрегация по дням                          │   │
│  │                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        PostgreSQL (config DB)                        │   │
│  │                                                                       │   │
│  │   • devices — Устройства (CRUD)                                     │   │
│  │   • organizations — Организации                                     │   │
│  │   • users — Пользователи                                            │   │
│  │   • notification_rules — Правила уведомлений                        │   │
│  │   • command_log — Журнал команд                                     │   │
│  │                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                             Redis 7                                   │   │
│  │                                                                       │   │
│  │   • device:{imei} — HASH (context + position + connection)          │   │
│  │   • pending_commands:{imei} — Очередь команд (ZSET)                 │   │
│  │   • command_status:{requestId} — Статус команды (HASH)              │   │
│  │   • unknown:{imei}:attempts — Rate limiting (STRING + TTL)          │   │
│  │   • Pub/Sub каналы для команд                                        │   │
│  │                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          Apache Kafka                                 │   │
│  │                                                                       │   │
│  │   • gps-events (12 partitions, 7 days) — Все GPS точки              │   │
│  │   • gps-events-rules (6 partitions, 7 days) — Точки с геозонами     │   │
│  │   • gps-events-unverified (6 partitions, 7 days) — DLQ              │   │
│  │   • device-status (6 partitions, 7 days) — Online/offline           │   │
│  │   • geozone-events (6 partitions, 30 days) — Enter/leave            │   │
│  │   • command-audit (3 partitions, 90 days) — Аудит команд            │   │
│  │                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🕐 TimescaleDB

### Конфигурация

```sql
-- Расширения
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- для полнотекстового поиска

-- Настройки для производительности
-- postgresql.conf
-- shared_preload_libraries = 'timescaledb'
-- timescaledb.max_background_workers = 8
```

### gps_points (hypertable)

**Назначение:** Хранение всех GPS точек (основная таблица)

```sql
CREATE TABLE gps_points (
    -- Идентификация
    id BIGSERIAL,
    device_id INTEGER NOT NULL,
    imei VARCHAR(20) NOT NULL,
    
    -- Время
    timestamp TIMESTAMPTZ NOT NULL,           -- время от трекера
    server_time TIMESTAMPTZ DEFAULT NOW(),    -- время получения сервером
    
    -- Координаты
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    altitude SMALLINT,                        -- метры
    
    -- Движение
    speed SMALLINT,                           -- км/ч * 10 (для точности без float)
    course SMALLINT,                          -- градусы (0-359)
    
    -- GPS качество
    satellites SMALLINT,
    hdop SMALLINT,                            -- * 10
    pdop SMALLINT,                            -- * 10
    valid BOOLEAN DEFAULT true,               -- валидный GPS fix
    
    -- Протокол
    protocol VARCHAR(15),                     -- teltonika, wialon, etc
    
    -- Сырые IO данные (датчики)
    io_data JSONB,                            -- {"1": 1, "66": 12500, "67": 4100}
    
    -- Первичный ключ для hypertable
    PRIMARY KEY (timestamp, device_id)
);

-- Создание hypertable (партиционирование по времени)
SELECT create_hypertable('gps_points', 'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Индексы
CREATE INDEX idx_gps_points_device_time 
    ON gps_points (device_id, timestamp DESC);

CREATE INDEX idx_gps_points_imei_time 
    ON gps_points (imei, timestamp DESC);

-- Пространственный индекс для запросов "точки в области"
CREATE INDEX idx_gps_points_coords 
    ON gps_points USING GIST (
        ST_SetSRID(ST_MakePoint(lon, lat), 4326)
    );

-- Сжатие для старых данных
ALTER TABLE gps_points SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',
    timescaledb.compress_orderby = 'timestamp DESC',
    timescaledb.compress_chunk_time_interval = '1 day'
);

-- Политика сжатия (данные старше 7 дней)
SELECT add_compression_policy('gps_points', INTERVAL '7 days');

-- Политика удаления (данные старше 90 дней)
SELECT add_retention_policy('gps_points', INTERVAL '90 days');
```

### sensor_data (hypertable)

**Назначение:** Калиброванные данные датчиков

```sql
CREATE TABLE sensor_data (
    device_id INTEGER NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    sensor_type VARCHAR(20) NOT NULL,         -- fuel_level, temperature, etc
    
    raw_value INTEGER,                        -- сырое значение ADC
    calibrated_value DECIMAL(10,2),           -- калиброванное значение
    unit VARCHAR(10),                         -- L, °C, V, etc
    
    PRIMARY KEY (timestamp, device_id, sensor_type)
);

SELECT create_hypertable('sensor_data', 'timestamp',
    chunk_time_interval => INTERVAL '1 day'
);

CREATE INDEX idx_sensor_data_device 
    ON sensor_data (device_id, sensor_type, timestamp DESC);

-- Сжатие
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id, sensor_type',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('sensor_data', INTERVAL '7 days');
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');
```

### geozones (PostGIS)

**Назначение:** Геозоны с геометрией

```sql
CREATE TABLE geozones (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id),
    
    -- Основное
    name VARCHAR(100) NOT NULL,
    description TEXT,
    zone_type VARCHAR(20) DEFAULT 'polygon',  -- polygon, circle, corridor
    
    -- Геометрия (PostGIS)
    geometry GEOMETRY(Geometry, 4326) NOT NULL,
    
    -- Для circle типа
    center_lat DOUBLE PRECISION,
    center_lon DOUBLE PRECISION,
    radius_meters DOUBLE PRECISION,
    
    -- Отображение
    color VARCHAR(7) DEFAULT '#FF0000',
    fill_opacity DECIMAL(3,2) DEFAULT 0.3,
    stroke_width INTEGER DEFAULT 2,
    
    -- Статус
    is_active BOOLEAN DEFAULT true,
    
    -- Служебное
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by INTEGER REFERENCES users(id)
);

-- GIST индекс для пространственных запросов
CREATE INDEX idx_geozones_geom 
    ON geozones USING GIST (geometry);

CREATE INDEX idx_geozones_org 
    ON geozones (organization_id) 
    WHERE is_active = true;

-- Bounding Box для быстрой предфильтрации
CREATE INDEX idx_geozones_bbox 
    ON geozones USING GIST (ST_Envelope(geometry));

-- Функция обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER geozones_updated_at
    BEFORE UPDATE ON geozones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### geozone_grid (Spatial Grid Cache)

**Назначение:** Кеш зон по ячейкам сетки

```sql
CREATE TABLE geozone_grid (
    grid_hash VARCHAR(20) PRIMARY KEY,        -- geohash или custom
    zone_ids INTEGER[] NOT NULL,              -- массив ID зон
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geozone_grid_updated 
    ON geozone_grid (updated_at);

-- Функция для получения зон по координатам
CREATE OR REPLACE FUNCTION get_zones_for_point(
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_org_id INTEGER
) RETURNS TABLE(zone_id INTEGER, zone_name VARCHAR) AS $$
BEGIN
    RETURN QUERY
    SELECT g.id, g.name
    FROM geozones g
    WHERE g.organization_id = p_org_id
      AND g.is_active = true
      AND ST_Covers(g.geometry, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326));
END;
$$ LANGUAGE plpgsql;
```

### geozone_events

**Назначение:** Журнал событий входа/выхода из геозон

```sql
CREATE TABLE geozone_events (
    id BIGSERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL,
    geozone_id INTEGER NOT NULL REFERENCES geozones(id),
    
    event_type VARCHAR(10) NOT NULL,          -- 'enter' или 'leave'
    timestamp TIMESTAMPTZ NOT NULL,           -- время события
    
    -- Координаты события
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    
    -- Дополнительно
    speed SMALLINT,
    address TEXT,                             -- reverse geocoded address
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geozone_events_device 
    ON geozone_events (device_id, timestamp DESC);

CREATE INDEX idx_geozone_events_zone 
    ON geozone_events (geozone_id, timestamp DESC);

-- Партиционирование по месяцам (опционально)
-- SELECT create_hypertable('geozone_events', 'timestamp',
--     chunk_time_interval => INTERVAL '1 month'
-- );
```

### trips

**Назначение:** Детальные поездки

```sql
CREATE TABLE trips (
    id BIGSERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL,
    
    -- Время
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER,
    
    -- Начальная точка
    start_lat DOUBLE PRECISION,
    start_lon DOUBLE PRECISION,
    start_address TEXT,
    
    -- Конечная точка
    end_lat DOUBLE PRECISION,
    end_lon DOUBLE PRECISION,
    end_address TEXT,
    
    -- Метрики
    distance_km DECIMAL(10,2),
    max_speed INTEGER,
    avg_speed DECIMAL(5,1),
    
    -- Топливо (если есть датчик)
    fuel_start DECIMAL(8,2),
    fuel_end DECIMAL(8,2),
    fuel_consumed DECIMAL(8,2),
    
    -- Служебное
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_trips_device 
    ON trips (device_id, start_time DESC);

CREATE INDEX idx_trips_time 
    ON trips (start_time DESC);
```

### device_daily_stats

**Назначение:** Агрегированная статистика по дням

```sql
CREATE TABLE device_daily_stats (
    device_id INTEGER NOT NULL,
    date DATE NOT NULL,
    
    -- Пробег
    total_distance_km DECIMAL(10,2),
    
    -- Время
    engine_hours INTEGER,                     -- минуты
    moving_time INTEGER,                      -- минуты
    idle_time INTEGER,                        -- минуты (двигатель вкл, скорость = 0)
    stopped_time INTEGER,                     -- минуты (двигатель выкл)
    
    -- Скорость
    max_speed INTEGER,
    avg_speed DECIMAL(5,1),
    
    -- Топливо
    fuel_consumed DECIMAL(8,2),
    fuel_refilled DECIMAL(8,2),
    fuel_drained DECIMAL(8,2),
    
    -- Счётчики
    trips_count INTEGER,
    stops_count INTEGER,
    speed_violations INTEGER,
    geozone_entries INTEGER,
    geozone_exits INTEGER,
    
    -- GPS качество
    points_count INTEGER,
    valid_points_count INTEGER,
    
    -- Служебное
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (device_id, date)
);

CREATE INDEX idx_daily_stats_date 
    ON device_daily_stats (date DESC);

-- Continuous Aggregate (автоматический пересчёт)
-- Требует TimescaleDB 2.0+
```

---

## 🗃️ PostgreSQL (Config DB)

### devices

**Назначение:** Управление устройствами (CRUD)

```sql
CREATE TABLE devices (
    id SERIAL PRIMARY KEY,
    
    -- Идентификация
    imei VARCHAR(20) UNIQUE NOT NULL,
    serial_number VARCHAR(50),
    
    -- Организация
    organization_id INTEGER NOT NULL REFERENCES organizations(id),
    
    -- Тип устройства
    device_type_id INTEGER REFERENCES device_types(id),
    protocol VARCHAR(20) NOT NULL,            -- teltonika, wialon, ruptela, navtelecom
    
    -- Транспортное средство
    name VARCHAR(100),
    description TEXT,
    vehicle_type VARCHAR(20),                 -- car, truck, bus, etc
    plate_number VARCHAR(20),
    vin VARCHAR(20),
    
    -- Контакт
    phone VARCHAR(20),                        -- SIM карта в трекере
    driver_id INTEGER REFERENCES drivers(id),
    
    -- Отображение на карте
    icon VARCHAR(50) DEFAULT 'car',
    color VARCHAR(7),
    
    -- Настройки
    settings JSONB DEFAULT '{}',
    -- {"min_speed_filter": 5, "max_speed": 150, "fuel_sensor": {...}}
    
    -- Статус
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ                    -- soft delete
);

CREATE INDEX idx_devices_org 
    ON devices (organization_id) 
    WHERE is_active = true AND deleted_at IS NULL;

CREATE INDEX idx_devices_imei 
    ON devices (imei);

CREATE TRIGGER devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### device_types

**Назначение:** Модели трекеров и их характеристики

```sql
CREATE TABLE device_types (
    id SERIAL PRIMARY KEY,
    
    name VARCHAR(50) NOT NULL,                -- "Teltonika FMB920"
    manufacturer VARCHAR(50),                 -- "Teltonika"
    protocol VARCHAR(20) NOT NULL,            -- "teltonika"
    
    -- Поддерживаемые команды
    commands JSONB DEFAULT '[]',
    -- [{"code": "reboot", "name": "Перезагрузка", "params": []}, ...]
    
    -- IO элементы (mapping)
    io_elements JSONB DEFAULT '{}',
    -- {"66": "external_voltage", "67": "battery_voltage", "239": "ignition"}
    
    -- Описание
    description TEXT,
    documentation_url TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### organizations

**Назначение:** Организации (мультитенантность)

```sql
CREATE TABLE organizations (
    id SERIAL PRIMARY KEY,
    
    name VARCHAR(100) NOT NULL,
    legal_name VARCHAR(200),
    
    -- Подписка
    subscription_type VARCHAR(20) DEFAULT 'trial',  -- trial, basic, pro, enterprise
    subscription_expires_at TIMESTAMPTZ,
    max_devices INTEGER DEFAULT 10,
    max_users INTEGER DEFAULT 3,
    
    -- Контакты
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    address TEXT,
    
    -- Настройки
    settings JSONB DEFAULT '{}',
    -- {"timezone": "Europe/Moscow", "language": "ru", "date_format": "DD.MM.YYYY"}
    
    -- Статус
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### users

**Назначение:** Пользователи системы

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id),
    
    -- Аутентификация
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    
    -- Профиль
    name VARCHAR(100),
    phone VARCHAR(20),
    avatar_url TEXT,
    
    -- Авторизация
    role VARCHAR(20) NOT NULL DEFAULT 'viewer',   -- admin, manager, operator, viewer
    permissions JSONB DEFAULT '[]',
    -- ["devices.read", "devices.write", "commands.send", "reports.create"]
    
    -- Ограничения
    allowed_device_ids INTEGER[],             -- NULL = все устройства org
    allowed_geozone_ids INTEGER[],
    
    -- Настройки
    settings JSONB DEFAULT '{}',
    -- {"notifications_email": true, "notifications_push": false}
    
    -- Статус
    is_active BOOLEAN DEFAULT true,
    last_login_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_org 
    ON users (organization_id) 
    WHERE is_active = true;

CREATE INDEX idx_users_email 
    ON users (email);
```

### notification_rules

**Назначение:** Правила уведомлений

```sql
CREATE TABLE notification_rules (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id),
    
    name VARCHAR(100) NOT NULL,
    description TEXT,
    
    -- Триггер
    event_type VARCHAR(50) NOT NULL,
    -- 'geozone_enter', 'geozone_leave', 'speed_exceed', 'fuel_drain', 'offline', etc
    
    -- Условия (фильтры)
    conditions JSONB NOT NULL DEFAULT '{}',
    -- {
    --   "device_ids": [1, 2, 3],           -- NULL = все
    --   "geozone_ids": [10, 20],           -- для geozone событий
    --   "threshold": 90,                    -- для speed_exceed
    --   "time_range": {"start": "08:00", "end": "18:00"},
    --   "days_of_week": [1, 2, 3, 4, 5]    -- 1 = Monday
    -- }
    
    -- Каналы доставки
    channels JSONB NOT NULL DEFAULT '[]',
    -- [
    --   {"type": "email", "recipients": ["a@b.com", "c@d.com"]},
    --   {"type": "sms", "phones": ["+79001234567"]},
    --   {"type": "push", "user_ids": [1, 2]},
    --   {"type": "webhook", "url": "https://api.example.com/hook", "headers": {...}}
    -- ]
    
    -- Шаблоны
    template_subject VARCHAR(200),
    template_body TEXT,
    -- Переменные: {device_name}, {event_time}, {speed}, {geozone_name}, etc
    
    -- Rate limiting
    cooldown_minutes INTEGER DEFAULT 5,       -- мин. интервал между уведомлениями
    max_per_hour INTEGER DEFAULT 10,
    max_per_day INTEGER DEFAULT 100,
    
    -- Статус
    is_active BOOLEAN DEFAULT true,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by INTEGER REFERENCES users(id)
);

CREATE INDEX idx_notification_rules_org 
    ON notification_rules (organization_id) 
    WHERE is_active = true;

CREATE INDEX idx_notification_rules_event 
    ON notification_rules (event_type) 
    WHERE is_active = true;
```

### command_log

**Назначение:** Журнал команд на устройства

```sql
CREATE TABLE command_log (
    id BIGSERIAL PRIMARY KEY,
    device_id INTEGER NOT NULL REFERENCES devices(id),
    
    -- Команда
    command_type VARCHAR(50) NOT NULL,        -- reboot, get_position, set_param, etc
    command_code VARCHAR(100),                -- raw command code
    payload JSONB,                            -- параметры команды
    
    -- Статус
    status VARCHAR(20) NOT NULL,              -- pending, sent, executed, failed, timeout
    error_message TEXT,
    response JSONB,                           -- ответ от трекера
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    timeout_at TIMESTAMPTZ,                   -- когда истекает ожидание ответа
    
    -- Кто отправил
    created_by INTEGER REFERENCES users(id)
);

CREATE INDEX idx_command_log_device 
    ON command_log (device_id, created_at DESC);

CREATE INDEX idx_command_log_status 
    ON command_log (status) 
    WHERE status IN ('pending', 'sent');
```

---

## 🔴 Redis 7

### Конфигурация

```redis
# redis.conf (основные настройки)
maxmemory 512mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
```

### Структуры данных

#### device:{imei} — Данные устройства (HASH)

**Единый ключ для всех данных устройства.** Записывается двумя сервисами:
- **Device Manager** — context поля (при CRUD)
- **Connection Manager** — position + connection поля (при работе трекера)

```redis
# === CONTEXT поля (Device Manager пишет) ===
HMSET device:860123456789012 \
    vehicleId 123 \
    organizationId 456 \
    name "Грузовик-001" \
    speedLimit 90 \
    hasGeozones true \
    hasSpeedRules false \
    fuelTankVolume 200

# === POSITION поля (Connection Manager пишет) ===
HMSET device:860123456789012 \
    lat 55.7558 \
    lon 37.6173 \
    speed 45 \
    course 180 \
    altitude 150 \
    satellites 12 \
    time 1706270400 \
    isMoving true \
    lastActivity 1706270450

# === CONNECTION поля (Connection Manager пишет) ===
HMSET device:860123456789012 \
    instanceId "cm-teltonika-01" \
    protocol "teltonika" \
    connectedAt 1706270000 \
    remoteAddress "192.168.1.100:54321"

# Чтение всех данных (один запрос!)
HGETALL device:860123456789012

# Размер: ~500 bytes per device
# 10,000 devices = ~5 MB

# БЕЗ TTL — данные персистентные
# Device Manager удаляет при DELETE устройства
```

#### pending_commands:{imei} — Очередь команд (ZSET)

```redis
# Структура (score = timestamp, для порядка)
ZADD pending_commands:860123456789012 1706270400 \
    '{"id":123,"type":"reboot","payload":{}}'

EXPIRE pending_commands:860123456789012 86400  # 24 часа

# Получить все команды для устройства
ZRANGE pending-cmd:860123456789012 0 -1

# Удалить выполненную команду
ZREM pending-cmd:860123456789012 '{"id":123,...}'

# Размер: ~200 bytes per command
# 1,000 pending commands = ~200 KB
```

#### Pub/Sub каналы

```redis
# Команды к устройству
PUBLISH cmd:860123456789012 '{"type":"reboot","id":123}'

# Ответы от устройства
PUBLISH cmd-response:860123456789012 '{"id":123,"status":"ok","response":"..."}'

# WebSocket broadcast
PUBLISH ws:org:456 '{"type":"position","device_id":123,"data":{...}}'
PUBLISH ws:device:123 '{"type":"position","data":{...}}'
PUBLISH ws:alerts:456 '{"type":"alert","device_id":123,"data":{...}}'
```

### Мониторинг Redis

```redis
# Статистика памяти
INFO memory

# Количество ключей по паттерну
SCAN 0 MATCH pos:* COUNT 1000

# Мониторинг Pub/Sub
PUBSUB CHANNELS cmd:*
PUBSUB NUMSUB cmd:860123456789012
```

---

## 📨 Apache Kafka

### Расчёт нагрузки

| Топик | Msg/sec | Размер | Throughput | Retention | Объём |
|-------|---------|--------|------------|-----------|-------|
| gps-events | 10,000 | ~200B | ~2 MB/s | 7 дней | ~1.2 TB |
| gps-events-rules | 3,000 | ~200B | ~0.6 MB/s | 7 дней | ~350 GB |
| gps-events-unverified | 100 | ~350B | ~35 KB/s | 7 дней | ~20 GB |
| device-status | 100 | ~150B | ~15 KB/s | 7 дней | ~10 GB |
| geozone-events | 500 | ~200B | ~100 KB/s | 30 дней | ~250 GB |
| command-audit | 50 | ~300B | ~15 KB/s | 90 дней | ~100 GB |

**Общий объём Kafka:** ~2 TB (нормально для одного брокера)

### Конфигурация кластера

```yaml
# docker-compose фрагмент
kafka:
  image: confluentinc/cp-kafka:7.5.0
  environment:
    KAFKA_BROKER_ID: 1
    KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
    KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
    KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
    KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
    KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
    KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"
    KAFKA_NUM_PARTITIONS: 6
    KAFKA_DEFAULT_REPLICATION_FACTOR: 1
    KAFKA_LOG_RETENTION_HOURS: 168  # 7 дней
    KAFKA_LOG_RETENTION_BYTES: 2147483648000  # 2 TB
```

### Topics

#### gps-events (основной поток)

**Назначение:** ВСЕ GPS точки для History Writer → TimescaleDB

```bash
kafka-topics --create \
  --topic gps-events \
  --partitions 12 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete \
  --config compression.type=lz4
```

**Schema (JSON):**
```json
{
  "vehicleId": 123,
  "organizationId": 456,
  "imei": "860123456789012",
  "timestamp": 1706270400000,
  "lat": 55.7558,
  "lon": 37.6173,
  "speed": 45,
  "course": 180,
  "altitude": 150,
  "satellites": 12,
  "protocol": "teltonika",
  "isMoving": true,
  "io_data": {"66": 12500, "67": 4100}
}
```

**Partitioning:** `hash(vehicleId) % 12` — гарантирует порядок для одного устройства

#### gps-events-rules (для бизнес-логики)

**Назначение:** Точки с флагами `hasGeozones=true` ИЛИ `hasSpeedRules=true`  
**Consumer:** Geozones Service, Speed Rules Engine

```bash
kafka-topics --create \
  --topic gps-events-rules \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete \
  --config compression.type=lz4
```

**Schema (JSON) — тот же что и gps-events:**
```json
{
  "vehicleId": 123,
  "organizationId": 456,
  "imei": "860123456789012",
  "timestamp": 1706270400000,
  "lat": 55.7558,
  "lon": 37.6173,
  "speed": 45,
  "hasGeozones": true,
  "hasSpeedRules": false,
  "speedLimit": 90
}
```

**Логика публикации (Connection Manager):**
```scala
// Публикуем в gps-events-rules только если есть правила
if (deviceData.hasGeozones || deviceData.hasSpeedRules)
  kafkaProducer.publish("gps-events-rules", enrichedPoint)
```

#### gps-events-unverified (DLQ)

**Назначение:** Dead Letter Queue для GPS точек, которые не удалось верифицировать  
**Producer:** Connection Manager  
**Consumer:** History Writer (для повторной обработки) или Admin Service (для мониторинга)

**Когда используется:**
- Redis недоступен (circuit breaker открыт)
- Устройство не зарегистрировано в системе
- Устройство деактивировано
- Ошибка валидации точки
- Несовпадение organizationId
- Ошибка парсинга протокола

```bash
kafka-topics --create \
  --topic gps-events-unverified \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete \
  --config compression.type=lz4
```

**Schema (JSON):**
```json
{
  "imei": "860123456789012",
  "protocol": "teltonika",
  "remoteAddress": "192.168.1.100:54321",
  "timestamp": 1706270400000,
  "lat": 55.7558,
  "lon": 37.6173,
  "speed": 45,
  "course": 180,
  "altitude": 150,
  "satellites": 12,
  "gpsTime": 1706270390000,
  "reason": "RedisUnavailable",
  "errorMessage": "Circuit breaker is open after 5 failures",
  "receivedAt": 1706270400000,
  "retryCount": 0
}
```

**UnverifiedReason enum:**
| Reason | Описание |
|--------|----------|
| `RedisUnavailable` | Circuit breaker Redis открыт, нет доступа к кэшу устройств |
| `DeviceNotFound` | IMEI не найден в Redis (устройство не зарегистрировано) |
| `DeviceInactive` | Устройство деактивировано администратором |
| `ValidationFailed` | Точка не прошла валидацию (невалидные координаты, скорость, и т.д.) |
| `OrganizationMismatch` | Несовпадение organizationId (потенциальная атака) |
| `ParseError` | Ошибка парсинга бинарного протокола |

**Логика обработки (History Writer):**
```scala
// Переодически читаем из DLQ и пытаемся повторно верифицировать
def processDlqBatch(events: List[UnverifiedGpsEvent]): Task[Unit] = for {
  verified <- ZIO.foreach(events) { event =>
    verifyDevice(event.imei).map {
      case Some(device) => Right(event.toGpsPoint(device))
      case None         => Left(event.copy(retryCount = event.retryCount + 1))
    }
  }
  // Успешно верифицированные → gps-events
  // Неуспешные с retryCount < 3 → обратно в DLQ
  // Неуспешные с retryCount >= 3 → unknown-devices или discard
} yield ()
```

#### device-status

**Назначение:** Online/offline события от Connection Manager

```bash
kafka-topics --create \
  --topic device-status \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=604800000
```

**Schema:**
```json
{
  "imei": "860123456789012",
  "vehicleId": 123,
  "isOnline": true,
  "lastSeen": 1706270400000,
  "disconnectReason": null,
  "sessionDurationMs": null
}
```

#### geozone-events

**Назначение:** События входа/выхода из геозон

```bash
kafka-topics --create \
  --topic geozone-events \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=2592000000 \
  --config cleanup.policy=delete
```

**Schema:**
```json
{
  "device_id": 123,
  "geozone_id": 456,
  "event_type": "enter",
  "timestamp": "2026-01-26T12:00:00Z",
  "lat": 55.7558,
  "lon": 37.6173,
  "speed": 5,
  "geozone_name": "Офис"
}
```

**Partitioning:** По `device_id % 6`

#### sensor-events

**Назначение:** События датчиков (заправки, сливы, превышения)

```bash
kafka-topics --create \
  --topic sensor-events \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=2592000000
```

**Schema:**
```json
{
  "device_id": 123,
  "event_type": "fuel_refill",
  "timestamp": "2026-01-26T12:00:00Z",
  "lat": 55.7558,
  "lon": 37.6173,
  "sensor_type": "fuel_level",
  "value_before": 45.5,
  "value_after": 98.2,
  "value_change": 52.7
}
```

#### alerts

**Назначение:** Все алерты (для Notifications Service)

```bash
kafka-topics --create \
  --topic alerts \
  --partitions 6 \
  --replication-factor 1 \
  --config retention.ms=2592000000
```

**Schema:**
```json
{
  "alert_type": "speed_exceed",
  "device_id": 123,
  "organization_id": 456,
  "timestamp": "2026-01-26T12:00:00Z",
  "data": {
    "speed": 120,
    "threshold": 90,
    "lat": 55.7558,
    "lon": 37.6173
  }
}
```

#### command-audit-log

**Назначение:** Аудит команд (compliance, отладка)

```bash
kafka-topics --create \
  --topic command-audit-log \
  --partitions 3 \
  --replication-factor 1 \
  --config retention.ms=7776000000 \
  --config cleanup.policy=delete
```

**Schema:**
```json
{
  "command_id": 999,
  "device_id": 123,
  "command_type": "reboot",
  "payload": {},
  "status": "executed",
  "response": "OK",
  "created_at": "2026-01-26T12:00:00Z",
  "completed_at": "2026-01-26T12:00:05Z",
  "user_id": 1
}
```

### Consumer Groups

```bash
# Просмотр групп
kafka-consumer-groups --list

# Consumer Groups:
# - history-writer-group (gps-events)
# - geozones-service-group (gps-events)
# - sensors-service-group (gps-events)
# - notifications-service-group (alerts, geozone-events, sensor-events)
# - websocket-service-group (gps-events, geozone-events, alerts)

# Проверка lag
kafka-consumer-groups --describe --group history-writer-group
```

---

## 📊 Размеры данных

### Оценка хранилища

| Компонент | Размер/день | Размер/месяц | Retention |
|-----------|------------|--------------|-----------|
| gps_points | ~10 GB | ~300 GB | 90 дней (сжатие после 7) |
| sensor_data | ~1 GB | ~30 GB | 90 дней |
| geozone_events | ~100 MB | ~3 GB | 1 год |
| trips | ~200 MB | ~6 GB | 1 год |
| Kafka logs | ~5 GB | ~35 GB | 7-30 дней |
| Redis | ~100 MB | N/A | In-memory |

### TimescaleDB сжатие

```sql
-- Проверка сжатия
SELECT 
    chunk_name,
    before_compression_total_bytes / 1024 / 1024 AS before_mb,
    after_compression_total_bytes / 1024 / 1024 AS after_mb,
    (1 - after_compression_total_bytes::float / before_compression_total_bytes) * 100 AS compression_ratio
FROM timescaledb_information.compressed_chunk_stats
ORDER BY chunk_name DESC
LIMIT 10;

-- Типичный результат: 85-90% сжатие
```

---

## 🔧 Миграции

### Порядок создания схемы

```bash
# 1. Создать базы данных
createdb tracker
createdb tracker_config

# 2. Применить расширения
psql -d tracker -f 01_extensions.sql

# 3. Создать таблицы (в порядке зависимостей)
psql -d tracker_config -f 02_organizations.sql
psql -d tracker_config -f 03_users.sql
psql -d tracker_config -f 04_device_types.sql
psql -d tracker_config -f 05_devices.sql
psql -d tracker_config -f 06_notification_rules.sql
psql -d tracker_config -f 07_command_log.sql

psql -d tracker -f 10_gps_points.sql
psql -d tracker -f 11_sensor_data.sql
psql -d tracker -f 12_geozones.sql
psql -d tracker -f 13_geozone_events.sql
psql -d tracker -f 14_trips.sql
psql -d tracker -f 15_device_daily_stats.sql

# 4. Создать Kafka топики
./scripts/create_kafka_topics.sh
```

---

**Дата:** 26 января 2026  
**Статус:** Data Stores документация готова ✅
