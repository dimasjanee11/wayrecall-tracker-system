# 🏗️ Архитектура Wayrecall Tracker System

## Обзор

Микросервисная GPS-система реального времени, построенная на Scala/ZIO с событийно-ориентированной архитектурой.

```
Трекеры (GPS устройства)
    ↓ TCP (Teltonika, Wialon, Ruptela, NavTelecom)
    ↓
┌─────────────────────────────────────────┐
│  Block 1: Data Collection & Flow       │
├─────────────────────────────────────────┤
│ Connection Manager (port 5001-5004)    │
│ ├─ TCP Server (Netty)                  │
│ ├─ GPS Protocol Parsers                │
│ ├─ Dead Reckoning Filter               │
│ ├─ Stationary Filter                   │
│ ├─ Redis cache (positions)             │
│ └─ Kafka publisher (gps-events)        │
│                                         │
│ History Writer                          │
│ ├─ Kafka consumer (gps-events)         │
│ ├─ Batch writer (500 points)           │
│ └─ TimescaleDB insert                  │
└─────────────────────────────────────────┘
    ↓ Kafka (gps-events topic)
    ↓
┌─────────────────────────────────────────┐
│  Block 2: Business Logic               │
├─────────────────────────────────────────┤
│ Geozone Service                        │
│ ├─ Reads: gps-events (moving only)    │
│ ├─ PostGIS queries (enter/leave)      │
│ └─ Publishes: geofence-events         │
│                                         │
│ Notification Service                   │
│ ├─ Rules engine                        │
│ ├─ Email/SMS/Push/Telegram             │
│ └─ Command routing                     │
│                                         │
│ Device Manager                          │
│ ├─ CRUD for devices                    │
│ ├─ Command queue (Redis ZSET)          │
│ ├─ Pending commands processing         │
│ └─ Device groups & templates           │
│                                         │
│ Analytics Service                      │
│ ├─ Reports (Excel/PDF/CSV)             │
│ ├─ Scheduled jobs                      │
│ └─ Data aggregation                    │
└─────────────────────────────────────────┘
    ↓ WebSocket / REST API
    ↓
┌─────────────────────────────────────────┐
│  Block 3: API & Frontend               │
├─────────────────────────────────────────┤
│ API Gateway (port 8080)                │
│ ├─ REST endpoints                      │
│ ├─ Authentication (JWT)                │
│ └─ Rate limiting                       │
│                                         │
│ WebSocket Service (port 8081)          │
│ ├─ Realtime positions                  │
│ ├─ Live alerts                         │
│ └─ Command results                     │
│                                         │
│ React Frontend (port 3000)             │
│ ├─ Map (Leaflet)                       │
│ ├─ Device list                         │
│ └─ Command panel                       │
└─────────────────────────────────────────┘
```

---

## 📦 Компоненты

### Connection Manager
**Роль:** Приём GPS данных и первичная обработка

**Входы:**
- TCP connections (port 5001-5004)
- Тракеры по 4 протоколам (Teltonika, Wialon, Ruptela, NavTelecom)

**Обработка:**
1. Parse GPS packet (protocol-specific)
2. Validate IMEI (Redis lookup)
3. Dead Reckoning Filter (координаты валидны?)
4. Stationary Filter (едет или стоит?)
5. Store in Redis (last position cache)
6. Publish to Kafka (gps-events topic)
7. Handle commands (Redis Pub/Sub)

**Выходы:**
- Redis: `position:{vehicleId}` (TTL 1h)
- Kafka: `gps-events` topic
- HTTP API (port 8080): config management

**Масштабирование:**
- Может быть несколько инстансов (за LB)
- Каждый тракер подключается к одному CM инстансу
- Connection registry в Redis

---

### History Writer
**Роль:** Сохранение GPS истории в TimescaleDB

**Входы:**
- Kafka: `gps-events` topic

**Обработка:**
1. Consume GPS events
2. Buffer до 500 points
3. Batch insert в TimescaleDB
4. Mark as processed (commit offset)

**Выходы:**
- TimescaleDB: таблица `gps_points`
- Metrics: insert latency, batch size

**Масштабирование:**
- Несколько инстансов (Kafka partitions)
- Каждый читает разные partitions
- Consumer group: `history-writer-group`

---

### Device Manager
**Роль:** Управление трекерами и командами

**Входы:**
- REST API (user commands)
- Redis: pending command queue

**Обработка:**
1. Create/Update/Delete device
2. Send command (if online)
3. Queue command (if offline)
4. Process pending on reconnect
5. Track command status

**Выходы:**
- Redis: `pending_commands:{imei}` (ZSET)
- Redis Pub/Sub: `commands:{imei}`
- Kafka: `command-audit-log` topic

**Команды:**
- `SET_INTERVAL` - интервал отправки GPS
- `GET_LOCATION` - запрос текущей позиции
- `REBOOT` - перезагрузка трекера
- `SET_OUTPUTS` - управление выходами
- `FIRMWARE_UPDATE` - обновление ПО
- `SET_GEOFENCES` - отправка геозон

---

### Geozone Service
**Роль:** Проверка входа/выхода из геозон

**Входы:**
- Kafka: `gps-events` (только `isMoving=true`)
- PostgreSQL: geofences (PostGIS geometries)

**Обработка:**
1. Get current position
2. Check all geofences (ST_Contains, ST_DWithin)
3. Compare with previous position
4. Detect enter/leave/inside events
5. Publish geofence-events

**Выходы:**
- Kafka: `geofence-events` topic
- PostgreSQL: `geofence_events` table
- Metrics: geofence check latency

---

### Notification Service
**Роль:** Отправка уведомлений

**Входы:**
- Kafka topics: `geofence-events`, `alerts`
- Rules engine configuration

**Обработка:**
1. Evaluate rules
2. Check notification channels
3. Send Email/SMS/Push/Telegram/WebSocket
4. Track delivery status

**Выходы:**
- External APIs (Email, SMS, Push)
- WebSocket: live notifications
- PostgreSQL: notification log

---

## 💾 Хранилища данных

### Redis
```
Key patterns:
- vehicle:{imei} → JSON (IMEI → VehicleId mapping)
- position:{vehicleId} → JSON (last position, TTL 1h)
- connection:{imei} → JSON (connection metadata)
- pending_commands:{imei} → ZSET (command queue by timestamp)
- device-config:{imei} → HASH (device settings)

Pub/Sub channels:
- commands:{imei} → command messages
- notifications:user_{userId} → user notifications
```

### TimescaleDB (PostgreSQL + PostGIS)
```sql
-- GPS история (hypertable)
CREATE TABLE gps_points (
  time TIMESTAMPTZ NOT NULL,
  vehicle_id BIGINT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  speed INTEGER,
  altitude INTEGER,
  course INTEGER,
  is_moving BOOLEAN,
  PRIMARY KEY (time, vehicle_id)
);
SELECT create_hypertable('gps_points', 'time');

-- Geofences (PostGIS)
CREATE TABLE geofences (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR,
  geometry GEOMETRY(Polygon),
  created_at TIMESTAMPTZ
);

-- Device grouping
CREATE TABLE devices (
  id BIGSERIAL PRIMARY KEY,
  imei VARCHAR UNIQUE,
  name VARCHAR,
  device_type VARCHAR,
  group_id BIGINT
);

-- Command audit log
CREATE TABLE command_events (
  time TIMESTAMPTZ NOT NULL,
  vehicle_id BIGINT,
  command_type VARCHAR,
  status VARCHAR,
  PRIMARY KEY (time, vehicle_id)
);
```

### Kafka Topics
```
- gps-events (12 partitions)
  Key: vehicleId
  Retention: 7 days
  Consumers: History Writer, Geozone Service, Analytics

- geofence-events (6 partitions)
  Key: vehicleId
  Retention: 30 days
  Consumers: Notification Service, UI WebSocket

- command-audit-log (3 partitions)
  Key: imei
  Retention: 90 days
  Consumers: Analytics, Monitoring

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

