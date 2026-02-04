# 🏗️ Архитектура Wayrecall Tracker System

> **Версия:** 3.0  
> **Дата обновления:** 4 февраля 2026  
> **Статус:** В разработке

---

## 📋 Обзор

Микросервисная GPS-система реального времени для мониторинга транспорта.

**Стек:** Scala 3 + ZIO 2 + Kafka + TimescaleDB + PostGIS + Redis

**Целевые показатели:**
- 10,000+ трекеров
- 10,000 GPS точек/сек
- Latency < 100ms (parse → Kafka)
- 99.9% uptime

---

## 🏛️ Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       GPS Трекеры (10K+ устройств)                          │
│                 Teltonika, Wialon, Ruptela, NavTelecom                      │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ TCP (ports 5001-5004)
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 1: СБОР И ОБРАБОТКА ДАННЫХ                                          │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Connection Manager                     History Writer                      │
│  ├─ TCP Server (Netty)                  ├─ Kafka consumer (gps-events)     │
│  ├─ Protocol Parsers (4 протокола)      ├─ Batch aggregation (500 pts)     │
│  ├─ Redis: getDeviceData(imei)          └─ TimescaleDB insert              │
│  ├─ Filters (Dead Reckoning, Stationary)                                   │
│  ├─ Kafka: gps-events (все точки)                                          │
│  └─ Kafka: gps-events-rules (точки с геозонами/правилами)                  │
│                                                                             │
│  Device Manager                                                             │
│  ├─ REST API (CRUD устройств)                                              │
│  ├─ Redis: device:{imei} (context fields)                                  │
│  ├─ PostgreSQL (master data)                                               │
│  └─ Daily Sync Job (Redis ↔ PostgreSQL)                                    │
│                                                                             │
│  Подробнее: docs/ARCHITECTURE_BLOCK1.md                                    │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ Kafka: gps-events, gps-events-rules
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 2: БИЗНЕС-ЛОГИКА                                                    │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Geozones Service                       Notifications Service               │
│  ├─ Kafka consumer (gps-events-rules)   ├─ Rules engine                    │
│  ├─ PostGIS: ST_Contains queries        ├─ Email/SMS/Push/Telegram         │
│  └─ Kafka producer: geozone-events      └─ Webhook integrations            │
│                                                                             │
│  Analytics Service                      Sensors Service                     │
│  ├─ Reports (Excel/PDF/CSV)             ├─ Fuel calibration                │
│  └─ Scheduled aggregation jobs          └─ Temperature monitoring          │
│                                                                             │
│  Подробнее: docs/ARCHITECTURE_BLOCK2.md                                    │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ REST / WebSocket
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 3: ПРЕДСТАВЛЕНИЕ                                                    │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  API Gateway                            WebSocket Service                   │
│  ├─ REST endpoints                      ├─ Realtime positions              │
│  ├─ JWT authentication                  ├─ Live alerts                     │
│  └─ Rate limiting                       └─ Command results                 │
│                                                                             │
│  Web Frontend (React + Leaflet)                                            │
│  ├─ Map с позициями                                                        │
│  ├─ Устройства и группы                                                    │
│  └─ Отчёты и уведомления                                                   │
│                                                                             │
│  Подробнее: docs/ARCHITECTURE_BLOCK3.md                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Потоки данных

### Data Flow: GPS Point

```
Трекер (TCP)
    ↓ Binary packet (Teltonika/Wialon/...)
Connection Manager
    ├─ Parse protocol → GpsRawPoint
    ├─ HGETALL device:{imei} → DeviceData (context + prev position)
    ├─ Validate IMEI (vehicleId exists?)
    ├─ Dead Reckoning Filter (скорость валидна?)
    ├─ Stationary Filter (едет или стоит?)
    ├─ Enrich point (vehicleId, orgId, hasGeozones, speedLimit)
    ├─ HMSET device:{imei} → update position fields
    ├─ Kafka: gps-events (ALL points)
    └─ Kafka: gps-events-rules (if hasGeozones OR hasSpeedRules)
         ↓                              ↓
    History Writer              Geozones Service
         ↓                              ↓
    TimescaleDB                 geozone-events
```

### Kafka Topics

| Топик | Partitions | Retention | Throughput | Consumer |
|-------|------------|-----------|------------|----------|
| **gps-events** | 12 | 7 дней | ~2 MB/s | History Writer |
| **gps-events-rules** | 6 | 7 дней | ~0.6 MB/s | Geozones Service |
| device-status | 6 | 7 дней | ~15 KB/s | Device Manager |
| geozone-events | 6 | 30 дней | ~100 KB/s | Notifications |
| command-audit | 3 | 90 дней | ~15 KB/s | Analytics |

---

## 💾 Хранилища данных

### Redis (HASH per device)

```
device:{imei}  (единый ключ на устройство)
├── CONTEXT (Device Manager пишет)
│   ├── vehicleId, organizationId, name
│   ├── speedLimit, hasGeozones, hasSpeedRules
│   └── fuelTankVolume
├── POSITION (Connection Manager пишет)
│   ├── lat, lon, speed, course, altitude
│   ├── satellites, time, isMoving
│   └── lastActivity
└── CONNECTION (Connection Manager пишет)
    ├── instanceId, protocol
    ├── connectedAt, remoteAddress
    └── (удаляется при disconnect)

pending_commands:{imei}  (ZSET, TTL 24h)
command_status:{requestId}  (HASH, TTL 1h)
unknown:{imei}:attempts  (STRING, TTL 1h)
```

### TimescaleDB

| Таблица | Тип | Сжатие | Retention |
|---------|-----|--------|-----------|
| gps_points | Hypertable | 15x после 7 дней | 90 дней |
| sensor_data | Hypertable | 10x после 7 дней | 90 дней |
| geozones | PostGIS | — | Permanent |
| geozone_events | Regular | — | 1 год |

### PostgreSQL (config)

- devices, device_groups
- organizations, users
- notification_rules
- command_log

---

## 📦 Список сервисов

### MVP (Block 1)

| # | Сервис | Порт | Статус |
|---|--------|------|--------|
| 1 | Connection Manager | TCP 5001-5004 | 🟡 В разработке |
| 2 | History Writer | — (Kafka consumer) | 🟡 В разработке |
| 3 | Device Manager | HTTP 8092 | 🟡 В разработке |

### Block 2 (Business Logic)

| # | Сервис | Описание | Статус |
|---|--------|----------|--------|
| 4 | Geozones Service | Enter/leave события | 📋 Спроектирован |
| 5 | Notifications Service | Email/SMS/Push/Telegram | 📋 Планируется |
| 6 | Analytics Service | Отчёты, агрегация | 📋 Планируется |
| 7 | Sensors Service | Топливо, температура | 📋 Планируется |

### Block 3 (Presentation)

| # | Сервис | Описание | Статус |
|---|--------|----------|--------|
| 8 | API Gateway | REST API, auth | 📋 Планируется |
| 9 | WebSocket Service | Realtime позиции | 📋 Планируется |
| 10 | Web Frontend | React + Leaflet | 📋 Планируется |

---

## 📈 Расчёт хранения

### Входные данные
- 10,000 трекеров
- 1 точка/сек (движущиеся ~30%)
- ~200 bytes/точка

### Объёмы

| Хранилище | Объём/день | Retention | Итого |
|-----------|------------|-----------|-------|
| **Kafka gps-events** | 170 GB | 7 дней | ~1.2 TB |
| **Kafka gps-events-rules** | 50 GB | 7 дней | ~350 GB |
| **TimescaleDB** (сжатые) | 11 GB | 90 дней | ~1 TB |
| **Redis** | ~5 MB | — | ~50 MB |

---

## 🎯 Порты

```
TCP (GPS protocols):
  5001: Teltonika
  5002: Wialon
  5003: Ruptela
  5004: NavTelecom

HTTP (internal):
  8092: Device Manager (REST API)
  8080: API Gateway (public)
  8081: WebSocket Gateway

Infrastructure:
  6379: Redis
  9092: Kafka
  5432: TimescaleDB / PostgreSQL
  9090: Prometheus
  3000: Grafana
```

---

## 📚 Связанные документы

- [ARCHITECTURE_BLOCK1.md](./ARCHITECTURE_BLOCK1.md) — Сбор данных
- [ARCHITECTURE_BLOCK2.md](./ARCHITECTURE_BLOCK2.md) — Бизнес-логика
- [ARCHITECTURE_BLOCK3.md](./ARCHITECTURE_BLOCK3.md) — Представление
- [DATA_STORES.md](./DATA_STORES.md) — Схемы хранилищ
- [services/CONNECTION_MANAGER.md](./services/CONNECTION_MANAGER.md) — Connection Manager
- [services/DEVICE_MANAGER.md](./services/DEVICE_MANAGER.md) — Device Manager

---

**Версия:** 3.0  
**Дата:** 4 февраля 2026
