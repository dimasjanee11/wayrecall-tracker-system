# 🏗️ Архитектура TrackerGPS System# 🏗️ Архитектура Wayrecall Tracker System



> **Версия:** 2.0  ## Обзор

> **Дата обновления:** 26 января 2026  

> **Статус:** В разработкеМикросервисная GPS-система реального времени, построенная на Scala/ZIO с событийно-ориентированной архитектурой.



---```

Трекеры (GPS устройства)

## 📋 Обзор    ↓ TCP (Teltonika, Wialon, Ruptela, NavTelecom)

    ↓

Микросервисная GPS-система реального времени для мониторинга транспорта.┌─────────────────────────────────────────┐

│  Block 1: Data Collection & Flow       │

**Стек:** Scala 3 + ZIO 2 + Kafka + TimescaleDB + PostGIS + Redis├─────────────────────────────────────────┤

│ Connection Manager (port 5001-5004)    │

**Целевые показатели:**│ ├─ TCP Server (Netty)                  │

- 10,000+ трекеров│ ├─ GPS Protocol Parsers                │

- 10,000 GPS точек/сек│ ├─ Dead Reckoning Filter               │

- Latency < 100ms (parse → Kafka)│ ├─ Stationary Filter                   │

- 99.9% uptime│ ├─ Redis cache (positions)             │

│ └─ Kafka publisher (gps-events)        │

---│                                         │

│ History Writer                          │

## 🏛️ Высокоуровневая архитектура│ ├─ Kafka consumer (gps-events)         │

│ ├─ Batch writer (500 points)           │

```│ └─ TimescaleDB insert                  │

┌─────────────────────────────────────────────────────────────────────────────┐└─────────────────────────────────────────┘

│                                                                             │    ↓ Kafka (gps-events topic)

│  GPS Трекеры (10K+ устройств)                                              │    ↓

│  Teltonika, Wialon, Ruptela, NavTelecom                                    │┌─────────────────────────────────────────┐

│                                                                             ││  Block 2: Business Logic               │

└─────────────────────────────┬───────────────────────────────────────────────┘├─────────────────────────────────────────┤

                              │ TCP (ports 5001-5004)│ Geozone Service                        │

                              ▼│ ├─ Reads: gps-events (moving only)    │

┌─────────────────────────────────────────────────────────────────────────────┐│ ├─ PostGIS queries (enter/leave)      │

│                                                                             ││ └─ Publishes: geofence-events         │

│  ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗     ██╗                         ││                                         │

│  ██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝    ███║                         ││ Notification Service                   │

│  ██████╔╝██║     ██║   ██║██║     █████╔╝     ╚██║                         ││ ├─ Rules engine                        │

│  ██╔══██╗██║     ██║   ██║██║     ██╔═██╗      ██║                         ││ ├─ Email/SMS/Push/Telegram             │

│  ██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗     ██║                         ││ └─ Command routing                     │

│  ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝     ╚═╝                         ││                                         │

│                                                                             ││ Device Manager                          │

│  СБОР И ОБРАБОТКА ДАННЫХ                                                   ││ ├─ CRUD for devices                    │

│  ───────────────────────────────────────────────────────────────────────── ││ ├─ Command queue (Redis ZSET)          │

│  • Connection Manager — приём TCP, парсинг протоколов, фильтрация         ││ ├─ Pending commands processing         │

│  • History Writer — батч-запись в TimescaleDB                             ││ └─ Device groups & templates           │

│  • Device Manager — CRUD устройств, команды, очередь                      ││                                         │

│                                                                             ││ Analytics Service                      │

│  Подробнее: docs/ARCHITECTURE_BLOCK1.md                                    ││ ├─ Reports (Excel/PDF/CSV)             │

│                                                                             ││ ├─ Scheduled jobs                      │

└─────────────────────────────┬───────────────────────────────────────────────┘│ └─ Data aggregation                    │

                              │ Kafka: gps-events└─────────────────────────────────────────┘

                              ▼    ↓ WebSocket / REST API

┌─────────────────────────────────────────────────────────────────────────────┐    ↓

│                                                                             │┌─────────────────────────────────────────┐

│  ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗    ██████╗                      ││  Block 3: API & Frontend               │

│  ██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝    ╚════██╗                     │├─────────────────────────────────────────┤

│  ██████╔╝██║     ██║   ██║██║     █████╔╝      █████╔╝                     ││ API Gateway (port 8080)                │

│  ██╔══██╗██║     ██║   ██║██║     ██╔═██╗     ██╔═══╝                      ││ ├─ REST endpoints                      │

│  ██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗    ███████╗                     ││ ├─ Authentication (JWT)                │

│  ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝    ╚══════╝                     ││ └─ Rate limiting                       │

│                                                                             ││                                         │

│  БИЗНЕС-ЛОГИКА                                                             ││ WebSocket Service (port 8081)          │

│  ───────────────────────────────────────────────────────────────────────── ││ ├─ Realtime positions                  │

│  • Geozones Service — проверка геозон, enter/leave события                ││ ├─ Live alerts                         │

│  • Notifications Service — правила, email/sms/push/webhook                ││ └─ Command results                     │

│  • Analytics Service — отчёты, агрегация                                  ││                                         │

│  • Sensors Service — обработка датчиков (топливо, температура)            ││ React Frontend (port 3000)             │

│                                                                             ││ ├─ Map (Leaflet)                       │

│  Подробнее: docs/ARCHITECTURE_BLOCK2.md                                    ││ ├─ Device list                         │

│                                                                             ││ └─ Command panel                       │

└─────────────────────────────┬───────────────────────────────────────────────┘└─────────────────────────────────────────┘

                              │ Kafka: alerts, geozone-events```

                              ▼

┌─────────────────────────────────────────────────────────────────────────────┐---

│                                                                             │

│  ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗    ██████╗                      │## 📦 Компоненты

│  ██╔══██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝    ╚════██╗                     │

│  ██████╔╝██║     ██║   ██║██║     █████╔╝      █████╔╝                     │### Connection Manager

│  ██╔══██╗██║     ██║   ██║██║     ██╔═██╗      ╚═══██╗                     │**Роль:** Приём GPS данных и первичная обработка

│  ██████╔╝███████╗╚██████╔╝╚██████╗██║  ██╗    ██████╔╝                     │

│  ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝    ╚═════╝                      │**Входы:**

│                                                                             │- TCP connections (port 5001-5004)

│  ПРЕДСТАВЛЕНИЕ                                                             │- Тракеры по 4 протоколам (Teltonika, Wialon, Ruptela, NavTelecom)

│  ───────────────────────────────────────────────────────────────────────── │

│  • API Gateway — REST API, JWT auth, rate limiting                        │**Обработка:**

│  • WebSocket Service — realtime позиции, alerts                           │1. Parse GPS packet (protocol-specific)<!-- Дополнение @AI: Трекер может прислать не только точку, но и батч точек, мы это умеем обрабатывать?-->

│  • Web Frontend — React + Leaflet карта                                   │2. Validate IMEI (Redis lookup)

│                                                                             │<!-- ToThink @AI: пункты 3 и 4 - зачем проверять на стоянку или на гиперскачек(кордината не валидна), если мы все равно обязаны сохранять все точки в БД? -->

│  Подробнее: docs/ARCHITECTURE_BLOCK3.md                                    │3. Dead Reckoning Filter (координаты валидны?)

│                                                                             │4. Stationary Filter (едет или стоит?)

└─────────────────────────────────────────────────────────────────────────────┘5. Store in Redis (last position cache)

```6. Publish to Kafka (gps-events topic)

7. Handle commands (Redis Pub/Sub)

---<!-- ToThink @AI: может стоит обощать точку еще какими то знаниями? протоколом там и тд-->



## 📦 Список сервисов**Выходы:**

- Redis: `position:{vehicleId}` (TTL 1h)<!-- Вопрос1 @AI: почему ТТЛ 1 час и что такое вообще ТТЛ -->

### MVP (первая версия)- Kafka: `gps-events` topic

- HTTP API (port 8080): config management <!-- Вопрос2 @AI: это для чего? Connection Manager разве куда то ходит по ресту?-->

| # | Сервис | Блок | Сложность | Статус |

|---|--------|------|-----------|--------|**Масштабирование:**

| 1 | Connection Manager | 1 | Высокая | 🟡 В разработке |- Может быть несколько инстансов (за LB)

| 2 | History Writer | 1 | Средняя | 🟡 В разработке |- Каждый тракер подключается к одному CM инстансу

| 3 | Device Manager | 1 | Средняя | 🟡 В разработке |- Connection registry в Redis <!-- Вопрос3 @AI: правильно ля я понимаю, что это для того чтоб знать на каком инстансе какие трекеры?-->

| 4 | Geozones Service | 2 | Высокая | 📋 Спроектирован |

| 5 | Notifications Service | 2 | Средняя | 📋 Планируется |---

| 6 | API Gateway | 3 | Средняя | 📋 Планируется |

| 7 | WebSocket Service | 3 | Средняя | 📋 Планируется |### History Writer

**Роль:** Сохранение GPS истории в TimescaleDB

### Production (расширенная версия)

**Входы:**

| # | Сервис | Блок | Описание |- Kafka: `gps-events` topic

|---|--------|------|----------|

| 8 | Analytics Service | 2 | Отчёты Excel/PDF, агрегация |**Обработка:**

| 9 | Sensors Service | 2 | Обработка датчиков |1. Consume GPS events

| 10 | Rules Engine | 2 | Маршрутизация событий (опционально) |2. Buffer до 500 points

| 11 | User Service | 3 | Управление пользователями |3. Batch insert в TimescaleDB

| 12 | Admin Service | 3 | Административная панель |4. Mark as processed (commit offset)



---**Выходы:**

- TimescaleDB: таблица `gps_points`

## 💾 Хранилища данных- Metrics: insert latency, batch size



### Обзор**Масштабирование:**

- Несколько инстансов (Kafka partitions)

```- Каждый читает разные partitions

┌─────────────────────────────────────────────────────────────────────────────┐- Consumer group: `history-writer-group`

│                           DATA STORES                                       │

├─────────────────────────────────────────────────────────────────────────────┤---

│                                                                             │

│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │### Device Manager

│  │   TimescaleDB   │  │    PostgreSQL   │  │     Redis       │            │**Роль:** Управление трекерами и командами

│  │   + PostGIS     │  │                 │  │                 │            │

│  │                 │  │                 │  │                 │            │**Входы:**

│  │  • gps_points   │  │  • devices      │  │  • positions    │            │- REST API (user commands)

│  │  • gps_sensors  │  │  • users        │  │  • connections  │            │- Redis: pending command queue

│  │  • geozones     │  │  • rules        │  │  • commands     │            │

│  │  • spatial_grid │  │  • orgs         │  │  • grid cache   │            │**Обработка:**

│  │                 │  │                 │  │  • geozone state│            │1. Create/Update/Delete device

│  │  10 GB/день     │  │  ~1 GB          │  │  ~100 MB        │            │2. Send command (if online)

│  └─────────────────┘  └─────────────────┘  └─────────────────┘            │3. Queue command (if offline)

│                                                                             │4. Process pending on reconnect

│  ┌─────────────────────────────────────────────────────────────┐          │5. Track command status

│  │                        Apache Kafka                         │          │

│  │                                                             │          │**Выходы:**

│  │  • gps-events (12 partitions, 7 days)                      │          │- Redis: `pending_commands:{imei}` (ZSET)

│  │  • geozone-events (6 partitions, 30 days)                  │          │- Redis Pub/Sub: `commands:{imei}`

│  │  • alerts (6 partitions, 30 days)                          │          │- Kafka: `command-audit-log` topic

│  │  • command-audit-log (3 partitions, 90 days)               │          │

│  └─────────────────────────────────────────────────────────────┘          │**Команды:**<!-- ToThink @AI: такие команды были в старом стелсе? и все ли команды со старого стелса мы учли?-->

│                                                                             │- `SET_INTERVAL` - интервал отправки GPS

│  Подробнее: docs/DATA_STORES.md                                            │- `GET_LOCATION` - запрос текущей позиции

│                                                                             │- `REBOOT` - перезагрузка трекера

└─────────────────────────────────────────────────────────────────────────────┘- `SET_OUTPUTS` - управление выходами

```- `FIRMWARE_UPDATE` - обновление ПО

- `SET_GEOFENCES` - отправка геозон

---

---

## 🔄 Основные потоки данных

### Geozone Service<!-- ToThink @AI: может не стоит постоянно проверять точку на вхождение в геозону? у нас будет 10к машин, 25-30к датчиков, по несколько датчиков в машине, и каждый раз чекать геозону странну, да еще и в оперативной памяти сервиса, может стоит пересмотреть логику, и сделать проверку геозон в бд, типо тригериться там?-->

### 1. GPS точка: трекер → база данных**Роль:** Проверка входа/выхода из геозон



```<!-- ToThink @AI: как работали проверки геозон в старом стелсе?-->

Трекер → TCP → Connection Manager → Kafka → History Writer → TimescaleDB

                     │**Входы:**

                     └→ Redis (last position cache)- Kafka: `gps-events` (только `isMoving=true`)

```- PostgreSQL: geofences (PostGIS geometries)



### 2. Проверка геозон**Обработка:**

1. Get current position

```2. Check all geofences (ST_Contains, ST_DWithin)

Kafka (gps-events) → Geozones Service → Kafka (geozone-events)3. Compare with previous position

                           │4. Detect enter/leave/inside events

                           ├→ Spatial Grid (Redis) — быстрая фильтрация5. Publish geofence-events

                           ├→ PostGIS (ST_Covers) — точная проверка

                           └→ State (Redis) — enter/leave detection**Выходы:**

```- Kafka: `geofence-events` topic

- PostgreSQL: `geofence_events` table

### 3. Отправка команды- Metrics: geofence check latency



```---

API → Device Manager → Redis Pub/Sub → Connection Manager → TCP → Трекер

           │### Notification Service<!-- ToThink @AI: тут может придеться переработать ибо тригериться еще не знаем пока на чем-->

           └→ Redis ZSET (pending commands) — если offline**Роль:** Отправка уведомлений

```

**Входы:**

---- Kafka topics: `geofence-events`, `alerts`

- Rules engine configuration

## 🎯 Порты

**Обработка:**

| Порт | Сервис | Протокол |1. Evaluate rules

|------|--------|----------|2. Check notification channels

| 5001 | Connection Manager | TCP (Teltonika) |3. Send Email/SMS/Push/Telegram/WebSocket

| 5002 | Connection Manager | TCP (Wialon) |4. Track delivery status

| 5003 | Connection Manager | TCP (Ruptela) |

| 5004 | Connection Manager | TCP (NavTelecom) |**Выходы:**

| 8080 | API Gateway | HTTP REST |- External APIs (Email, SMS, Push)

| 8081 | WebSocket Service | WebSocket |- WebSocket: live notifications

| 3000 | Web Frontend | HTTP |- PostgreSQL: notification log

| 5432 | TimescaleDB | PostgreSQL |

| 6379 | Redis | Redis |---

| 9092 | Kafka | Kafka |

| 9090 | Prometheus | HTTP |## 💾 Хранилища данных

| 3001 | Grafana | HTTP |

### Redis<!-- Поясни @AI: я пока не совсем разобрался с редисом, нужно чтоб ты поянил что для чего и как работает, я тупой-->

---```

Key patterns:

## 📊 Производительность- vehicle:{imei} → JSON (IMEI → VehicleId mapping)

- position:{vehicleId} → JSON (last position, TTL 1h)

### Целевые показатели- connection:{imei} → JSON (connection metadata)

- pending_commands:{imei} → ZSET (command queue by timestamp)

| Метрика | Значение |- device-config:{imei} → HASH (device settings)

|---------|----------|

| Трекеров | 10,000+ |Pub/Sub channels:

| GPS точек/сек | 10,000 |- commands:{imei} → command messages

| Latency (parse → Kafka) | < 50ms |- notifications:user_{userId} → user notifications

| Latency (parse → DB) | < 200ms |```

| Geozones проверок/сек | 2,000 (после оптимизаций) |

| PostGIS запросов/сек | ~10 (после всех кешей) |### TimescaleDB (PostgreSQL + PostGIS)

```sql

### Масштабирование-- GPS история (hypertable)

CREATE TABLE gps_points (<!-- ToThink @AI: может есть смысл хранить точку еще с протоколом или еще какими данными от трекера? обощать метаданными? или под эту задачу лучше завестит отдельную таблицу в пострегсе?-->

| Сервис | Стратегия |  time TIMESTAMPTZ NOT NULL,

|--------|-----------|  vehicle_id BIGINT NOT NULL,

| Connection Manager | Горизонтальное (за LB), session в Redis |  latitude DOUBLE PRECISION,

| History Writer | Kafka Consumer Group (по партициям) |  longitude DOUBLE PRECISION,

| Geozones Service | Kafka Consumer Group + Redis cache |  speed INTEGER,

| API Gateway | Горизонтальное (stateless) |  altitude INTEGER,

  course INTEGER,

---  is_moving BOOLEAN,

  PRIMARY KEY (time, vehicle_id)

## 📚 Детальная документация);

SELECT create_hypertable('gps_points', 'time');

| Документ | Описание |

|----------|----------|-- Geofences (PostGIS)

| [ARCHITECTURE_BLOCK1.md](./ARCHITECTURE_BLOCK1.md) | Block 1: Сбор данных |CREATE TABLE geofences (

| [ARCHITECTURE_BLOCK2.md](./ARCHITECTURE_BLOCK2.md) | Block 2: Бизнес-логика |  id BIGSERIAL PRIMARY KEY,

| [ARCHITECTURE_BLOCK3.md](./ARCHITECTURE_BLOCK3.md) | Block 3: Представление |  name VARCHAR,

| [DATA_STORES.md](./DATA_STORES.md) | Схемы БД, Kafka, Redis |  geometry GEOMETRY(Polygon),

| [GEOZONES_SERVICE_DESIGN.md](./GEOZONES_SERVICE_DESIGN.md) | Дизайн сервиса геозон |  created_at TIMESTAMPTZ

| [GEOZONES_DETAILED_FAQ.md](./GEOZONES_DETAILED_FAQ.md) | FAQ по геозонам |);

| [STELS_GEOZONE_ANALYSIS.md](./STELS_GEOZONE_ANALYSIS.md) | Анализ старого Stels |

-- Device grouping

---CREATE TABLE devices (

  id BIGSERIAL PRIMARY KEY,

## 🔐 Безопасность  imei VARCHAR UNIQUE,

  name VARCHAR,

- JWT authentication для API  device_type VARCHAR,

- IMEI validation через Redis  group_id BIGINT

- TLS для Kafka (production));

- SSL для PostgreSQL

- Rate limiting на API Gateway-- Command audit log

- Input validation для всех протоколовCREATE TABLE command_events (

  time TIMESTAMPTZ NOT NULL,

---  vehicle_id BIGINT,

  command_type VARCHAR,

## 📈 Мониторинг  status VARCHAR,

  PRIMARY KEY (time, vehicle_id)

**Prometheus метрики:**);

- `gps_packets_received_total{protocol, status}````

- `gps_connections_active{protocol}`

- `gps_parse_latency_ms`### Kafka Topics <!-- ToThink @AI: поясни за выбранные конфигурации-->

- `kafka_publish_latency_ms````

- `geozones_check_latency_ms`- gps-events (12 partitions)

- `geozones_cache_hit_rate`  Key: vehicleId

  Retention: 7 days

**Grafana дашборды:**  Consumers: History Writer, Geozone Service, Analytics

- GPS throughput в реальном времени

- Количество подключений по протоколам- geofence-events (6 partitions)

- Latency percentiles (p50, p95, p99)  Key: vehicleId

- Error rates  Retention: 30 days

- Geozones performance  Consumers: Notification Service, UI WebSocket



---- command-audit-log (3 partitions)

  Key: imei

**Дата:** 26 января 2026    Retention: 90 days

**Статус:** Обзорный документ обновлён ✅  Consumers: Analytics, Monitoring


- device-status (3 partitions)
  Key: imei
  Retention: 30 days
  Consumers: Notification Service, Monitoring

- alerts (3 partitions)
  Key: userId
  Retention: 30 days
  Consumers: Notification Service
```

---

## 🔄 Data Flow

### 1. GPS Point Ingestion
```
Тракер → TCP connection to CM → Parse protocol
         ↓
         Validate (Dead Reckoning)
         ↓
         Check if moving (Stationary Filter)
         ↓
         Store in Redis: position:{vehicleId}
         ↓
         Publish to Kafka: gps-events (with flags: isMoving, validationPassed)
         ↓
         History Writer reads from Kafka
         ↓
         Batch insert into TimescaleDB
```

### 2. Geofence Detection
```
GPS point (isMoving=true) in Kafka
         ↓
         Geozone Service reads
         ↓
         Query: Which geofences contain this point?
         ↓
         Compare with previous position:
           - Entered geofence?
           - Left geofence?
           - Still inside?
         ↓
         Publish: geofence-events to Kafka
         ↓
         Notification Service processes
         ↓
         Send notifications to user
```

### 3. Command Execution
```
User sends command via API
         ↓
         Device Manager checks: Is device online?
         ↓
         YES → Send via Redis Pub/Sub (realtime)
               ├─ Connection Manager receives
               ├─ Send via TCP
               ├─ Wait ACK (30 sec)
               └─ Publish: command-audit-log
         ↓
         NO → Queue in Redis ZSET: pending_commands:{imei}
              (TTL 24h, score=timestamp for FIFO)
              ↓
              Device connects → onConnect event
              ↓
              Device Manager: processPendingCommands(imei)
              ├─ ZRANGE pending_commands:{imei}
              ├─ Send SEQUENTIALLY (maintain order!)
              ├─ Wait ACK for each
              ├─ Retry on failure (max 3)
              └─ ZREM after success
```

---

## 🎯 Порты

```
TCP:
- 5001: Teltonika GPS protocol
- 5002: Wialon GPS protocol
- 5003: Ruptela GPS protocol
- 5004: NavTelecom GPS protocol

HTTP:
- 8080: API Gateway (REST)
- 8081: WebSocket Gateway (realtime)
- 3000: React Frontend

Internal:
- 6379: Redis
- 9092: Kafka
- 5432: TimescaleDB
- 9090: Prometheus (metrics)
- 3000: Grafana (dashboards)
```

---

## 📈 Производительность & Масштабирование

### Throughput Targets
```
- 10,000 тракеров
- 1 GPS point/sec per tracker (avg)
= 10,000 GPS events/sec

Latency targets:
- GPS parse: <10ms
- Dead Reckoning validation: <5ms
- Redis cache: <5ms
- Kafka publish: <10ms
= Total Connection Manager: <50ms

History Writer:
- Batch 500 points = 50 ms latency
- TimescaleDB insert: ~100ms for 500 points
- Total: <200ms
```

### Scalability
```
Connection Manager:
- Stateless (session in Redis)
- Can run 3-10 instances (behind LB)
- Each handles 1000-2000 connections

History Writer:
- Parallel (multiple instances)
- Consumer Group: partition per instance
- 12 Kafka partitions = 12 History Writers max

Geozone Service:
- Parallel (multiple instances)
- Consumer Group: partition per instance
- Lighter than History Writer (no DB writes)

Notification Service:
- Queue-based (can handle burst)
- External APIs (email, SMS) are bottleneck
```

---

## 🔐 Security

- JWT authentication for API
- IMEI validation via Redis lookup
- TLS for Kafka (production)
- SSL/TLS for database connections
- Rate limiting per user/API key
- Input validation (all protocols)

---

## 📊 Monitoring

Metrics (Prometheus):
- `gps_packets_received_total{protocol, status}`
- `gps_connections_active{protocol}`
- `gps_parse_latency_ms`
- `kafka_latency_ms`
- `redis_latency_ms`
- `timescaledb_insert_latency_ms`
- `command_execution_duration_ms{status}`

Dashboards (Grafana):
- Realtime GPS throughput
- Connection count by protocol
- Latency percentiles (p50, p95, p99)
- Error rates
- Device status overview

---

**Архитектура готова к масштабированию до 100K+ тракеров!** 🚀



<!-- Замечание @AI: в архитектуре разобраны сервисы, но не все, для мвп нам надо кучу еще других - 
Geozone Service
Notification Service
Analytics Service
Integration Service
Sensor Service
Maintenance Service
Route Service
User Service
Admin Service
Payment Service
Real-time monitoring Service

Web

Api Gateway Service 



-->

