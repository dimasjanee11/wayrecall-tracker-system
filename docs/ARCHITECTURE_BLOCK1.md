# 🔌 Block 1: Сбор и обработка данных

> **Ответственность:** Приём GPS данных, парсинг, фильтрация, запись в хранилище  
> **Сервисы:** Connection Manager, History Writer, Device Manager

---

## 📋 Обзор блока

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BLOCK 1: DATA COLLECTION                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────┐        ┌───────────────┐        ┌───────────────┐       │
│  │     GPS       │  TCP   │  Connection   │ Kafka  │   History     │       │
│  │   Трекеры     │───────▶│   Manager     │───────▶│   Writer      │       │
│  │               │        │               │        │               │       │
│  └───────────────┘        └───────┬───────┘        └───────┬───────┘       │
│                                   │                        │               │
│                                   │ Redis                  │ Batch         │
│                                   ▼                        ▼               │
│                           ┌───────────────┐        ┌───────────────┐       │
│                           │     Redis     │        │  TimescaleDB  │       │
│                           │  • positions  │        │  • gps_points │       │
│                           │  • connections│        │               │       │
│                           └───────────────┘        └───────────────┘       │
│                                   ▲                                        │
│                                   │ CRUD, Commands                         │
│                           ┌───────┴───────┐                                │
│                           │    Device     │                                │
│                           │   Manager     │                                │
│                           │               │                                │
│                           └───────────────┘                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Потоки данных Block 1

```mermaid
flowchart LR
    subgraph Devices["🚗 GPS Трекеры"]
        T1[Teltonika]
        T2[Wialon]
        T3[Ruptela]
        T4[NavTelecom]
    end

    subgraph CM["Connection Manager"]
        TCP[TCP Server]
        Parser[Protocol Parser]
        Filter[Filter & Validate]
        Publisher[Kafka Publisher]
    end

    subgraph Stores["Хранилища"]
        Kafka[(Kafka gps-events)]
        Redis[(Redis)]
        TSDB[(TimescaleDB)]
    end

    subgraph HW["History Writer"]
        Consumer[Kafka Consumer]
        Batcher[Batch Aggregator]
        Writer[DB Writer]
    end

    subgraph DM["Device Manager"]
        API[REST API]
        CmdQueue[Command Queue]
    end

    T1 & T2 & T3 & T4 --> TCP
    TCP --> Parser --> Filter --> Publisher
    Publisher --> Kafka
    Filter -.-> |last position| Redis
    
    Kafka --> Consumer --> Batcher --> Writer --> TSDB
    
    API --> Redis
    CmdQueue -.-> |Pub/Sub| TCP
```

---

## 🖥️ Connection Manager

### Обзор

**Ответственность:** Приём TCP подключений, парсинг протоколов, фильтрация, публикация в Kafka

**Порты:**
| Порт | Протокол |
|------|----------|
| 5001 | Teltonika FM |
| 5002 | Wialon IPS/NIS |
| 5003 | Ruptela |
| 5004 | NavTelecom |

### Архитектура сервиса

```mermaid
flowchart TB
    subgraph Incoming["Входящие подключения"]
        P5001[":5001 Teltonika"]
        P5002[":5002 Wialon"]
        P5003[":5003 Ruptela"]
        P5004[":5004 NavTelecom"]
    end

    subgraph TCPLayer["TCP Layer (ZIO)"]
        Acceptor[Connection Acceptor]
        ChannelPool[Channel Pool]
        Handler[Message Handler]
    end

    subgraph Parsers["Protocol Parsers"]
        TP[TeltonikaParser]
        WP[WialonParser]
        RP[RuptelaParser]
        NP[NavTelecomParser]
    end

    subgraph Pipeline["Processing Pipeline"]
        Validate[Validator]
        Filter[Distance/Time Filter]
        Transform[Transform to GpsPoint]
    end

    subgraph Output["Output"]
        KafkaPub[Kafka Publisher]
        RedisCache[Redis Position Cache]
    end

    P5001 & P5002 & P5003 & P5004 --> Acceptor
    Acceptor --> ChannelPool --> Handler
    Handler --> TP & WP & RP & NP
    TP & WP & RP & NP --> Validate --> Filter --> Transform
    Transform --> KafkaPub
    Transform --> RedisCache
```

### Ключевые компоненты

#### 1. TCP Server (ZIO)

```scala
// Упрощённая структура
trait ConnectionManager:
  def start: Task[Unit]
  def shutdown: Task[Unit]
  def metrics: Task[ConnectionMetrics]

case class ConnectionMetrics(
  activeConnections: Map[Protocol, Int],
  totalReceived: Long,
  totalErrors: Long
)
```

#### 2. Protocol Parser (Trait)

```scala
trait ProtocolParser[F[_]]:
  def parse(bytes: Chunk[Byte]): F[ParseResult]
  def buildAck(result: ParseResult): Chunk[Byte]
  def protocolName: String

sealed trait ParseResult
case class GpsPacket(
  imei: String,
  points: List[RawGpsPoint],
  ioData: Map[Int, Long]
) extends ParseResult
case class LoginRequest(imei: String) extends ParseResult
case class ParseError(reason: String) extends ParseResult
```

#### 3. Filter (Фильтрация точек)

```scala
// Правила фильтрации
case class FilterConfig(
  minDistanceMeters: Double = 5.0,    // игнорировать если < 5м
  minTimeSecs: Int = 5,               // игнорировать если < 5 сек
  maxSpeed: Double = 300.0,           // отбросить если > 300 км/ч (GPS глюк)
  invalidCoords: Boolean = true       // отбросить 0,0 координаты
)
```

### Sequence Diagram: Подключение трекера

```mermaid
sequenceDiagram
    participant T as Трекер
    participant CM as Connection Manager
    participant R as Redis
    participant K as Kafka

    T->>CM: TCP Connect :5001
    CM->>CM: Accept connection
    
    T->>CM: Login packet (IMEI)
    CM->>R: GET device:{imei}
    R-->>CM: Device config
    
    alt IMEI найден
        CM->>CM: Store connection in memory
        CM->>R: SET conn:{imei} = {nodeId, timestamp}
        CM-->>T: ACK (login success)
    else IMEI не найден
        CM-->>T: NACK (reject)
        CM->>CM: Close connection
    end

    loop GPS пакеты
        T->>CM: GPS packet (N points)
        CM->>CM: Parse protocol
        CM->>CM: Validate & Filter
        CM->>K: Publish to gps-events
        CM->>R: SET pos:{imei} = {lat, lon, speed, ts}
        CM-->>T: ACK
    end

    T->>CM: Disconnect / Timeout
    CM->>R: DEL conn:{imei}
    CM->>CM: Cleanup connection
```

### Redis структуры

```
# Последняя позиция устройства (для фильтрации и API)
pos:{imei}
  lat: 55.7558
  lon: 37.6173
  speed: 45.5
  course: 180
  timestamp: 1706270400
  TTL: 86400 (1 день)

# Активное подключение
conn:{imei}
  nodeId: "cm-node-1"
  connectedAt: 1706270000
  protocol: "teltonika"
  TTL: 300 (5 минут, обновляется)

# IMEI whitelist (для быстрой проверки)
imei:valid:{imei}
  deviceId: 123
  orgId: 456
  TTL: 3600 (1 час, обновляется Device Manager)
```

### Prometheus метрики

```
# Активные подключения по протоколам
gps_connections_active{protocol="teltonika"} 3500
gps_connections_active{protocol="wialon"} 2100

# Полученные пакеты
gps_packets_received_total{protocol="teltonika", status="success"} 1000000
gps_packets_received_total{protocol="teltonika", status="parse_error"} 150
gps_packets_received_total{protocol="teltonika", status="filtered"} 25000

# Latency
gps_parse_duration_ms{protocol="teltonika", quantile="0.5"} 0.8
gps_parse_duration_ms{protocol="teltonika", quantile="0.99"} 5.2

# Kafka publish
kafka_publish_duration_ms{topic="gps-events", quantile="0.5"} 1.2
kafka_publish_duration_ms{topic="gps-events", quantile="0.99"} 8.5
```

---

## 📝 History Writer

### Обзор

**Ответственность:** Consume из Kafka, батчирование, запись в TimescaleDB

**Особенности:**
- Kafka Consumer Group (масштабируется по партициям)
- Batch insert (1000 записей или 1 секунда)
- Idempotent writes (по IMEI + timestamp)

### Архитектура сервиса

```mermaid
flowchart TB
    subgraph Kafka["Kafka"]
        Topic[gps-events\n12 partitions]
    end

    subgraph Consumers["History Writer Instances"]
        C1[Consumer 1\npartitions 0-3]
        C2[Consumer 2\npartitions 4-7]
        C3[Consumer 3\npartitions 8-11]
    end

    subgraph Processing["Processing (per consumer)"]
        Deser[Deserialize]
        Batch[Batch Aggregator\n1000 records / 1 sec]
        Transform[Transform to SQL]
    end

    subgraph DB["TimescaleDB"]
        Insert[COPY / Batch INSERT]
        Hypertable[gps_points\nhypertable]
    end

    Topic --> C1 & C2 & C3
    C1 & C2 & C3 --> Deser --> Batch --> Transform --> Insert --> Hypertable
```

### Sequence Diagram: Запись батча

```mermaid
sequenceDiagram
    participant K as Kafka
    participant HW as History Writer
    participant B as Batch Buffer
    participant DB as TimescaleDB

    loop Consume loop
        K->>HW: Poll messages (max 500)
        HW->>HW: Deserialize GpsPoint
        HW->>B: Add to buffer
        
        alt Buffer >= 1000 OR timeout 1s
            B->>HW: Flush buffer
            HW->>DB: BEGIN
            HW->>DB: COPY gps_points FROM STDIN
            DB-->>HW: Rows inserted
            HW->>DB: COMMIT
            HW->>K: Commit offsets
        end
    end
```

### Ключевые компоненты

#### 1. Batch Aggregator

```scala
trait BatchAggregator[A]:
  def add(item: A): Task[Option[Chunk[A]]]  // возвращает batch если готов
  def flush: Task[Chunk[A]]                  // принудительный flush
  
case class BatchConfig(
  maxSize: Int = 1000,
  maxWait: Duration = 1.second
)
```

#### 2. DB Writer

```scala
trait GpsPointWriter:
  def writeBatch(points: Chunk[GpsPoint]): Task[Int]  // returns rows written

// Использует COPY для максимальной производительности
// INSERT ... ON CONFLICT DO NOTHING для idempotency
```

### TimescaleDB схема

```sql
-- Hypertable для GPS точек
CREATE TABLE gps_points (
    id BIGSERIAL,
    device_id INTEGER NOT NULL,
    imei VARCHAR(20) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    altitude SMALLINT,
    speed SMALLINT,            -- км/ч * 10 (для экономии места)
    course SMALLINT,           -- градусы
    satellites SMALLINT,
    hdop SMALLINT,             -- * 10
    valid BOOLEAN DEFAULT true,
    io_data JSONB,             -- дополнительные датчики
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (timestamp, device_id)
);

-- Превращаем в hypertable (партиции по времени)
SELECT create_hypertable('gps_points', 'timestamp',
    chunk_time_interval => INTERVAL '1 day'
);

-- Индексы
CREATE INDEX idx_gps_points_device_time 
    ON gps_points (device_id, timestamp DESC);
    
CREATE INDEX idx_gps_points_imei 
    ON gps_points (imei, timestamp DESC);

-- Сжатие для старых данных
ALTER TABLE gps_points SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);

-- Политика сжатия (данные старше 7 дней)
SELECT add_compression_policy('gps_points', INTERVAL '7 days');

-- Политика удаления (данные старше 90 дней)
SELECT add_retention_policy('gps_points', INTERVAL '90 days');
```

### Prometheus метрики

```
# Batch размеры
history_writer_batch_size{quantile="0.5"} 850
history_writer_batch_size{quantile="0.99"} 1000

# Latency записи
history_writer_write_duration_ms{quantile="0.5"} 45
history_writer_write_duration_ms{quantile="0.99"} 150

# Throughput
history_writer_points_written_total 50000000
history_writer_batches_written_total 52000

# Consumer lag
kafka_consumer_lag{topic="gps-events", partition="0"} 150
```

---

## 📱 Device Manager

### Обзор

**Ответственность:** CRUD устройств, отправка команд, синхронизация конфигураций

**Функции:**
- Управление устройствами (CRUD)
- Отправка команд на трекеры
- Очередь команд для offline устройств
- Синхронизация конфигов в Redis

### Архитектура сервиса

```mermaid
flowchart TB
    subgraph Clients["Клиенты"]
        API[API Gateway]
        Admin[Admin Panel]
    end

    subgraph DM["Device Manager"]
        REST[REST Controller]
        DeviceService[Device Service]
        CommandService[Command Service]
    end

    subgraph Storage["Хранилища"]
        PG[(PostgreSQL\ndevices table)]
        Redis[(Redis\ncommand queue)]
    end

    subgraph CM["Connection Manager"]
        TCPHandler[TCP Handler]
    end

    API & Admin --> REST
    REST --> DeviceService & CommandService
    DeviceService --> PG
    DeviceService --> Redis
    CommandService --> Redis
    Redis -.-> |Pub/Sub| TCPHandler
    TCPHandler -.-> |response| Redis
```

### Sequence Diagram: Отправка команды

```mermaid
sequenceDiagram
    participant UI as Web UI
    participant API as API Gateway
    participant DM as Device Manager
    participant R as Redis
    participant CM as Connection Manager
    participant T as Трекер

    UI->>API: POST /devices/123/commands {type: "reboot"}
    API->>DM: Send command request
    DM->>R: GET conn:{imei}
    
    alt Устройство онлайн
        R-->>DM: {nodeId: "cm-1", ...}
        DM->>R: PUBLISH cmd:{imei} {command}
        R-->>CM: Command notification
        CM->>T: Send command packet
        T-->>CM: ACK/Response
        CM->>R: PUBLISH cmd-response:{imei} {result}
        R-->>DM: Response notification
        DM-->>API: {status: "executed", response: ...}
    else Устройство оффлайн
        R-->>DM: null
        DM->>R: ZADD pending-cmd:{imei} {timestamp} {command}
        DM-->>API: {status: "queued", queuePosition: 3}
    end

    API-->>UI: Command result
```

### Sequence Diagram: Обработка очереди при подключении

```mermaid
sequenceDiagram
    participant T as Трекер
    participant CM as Connection Manager
    participant R as Redis

    T->>CM: Login (IMEI)
    CM->>R: ZRANGE pending-cmd:{imei} 0 -1
    R-->>CM: [{cmd1}, {cmd2}, ...]
    
    loop Каждая команда в очереди
        CM->>T: Send command
        T-->>CM: ACK/Response
        CM->>R: ZREM pending-cmd:{imei} {cmd}
        CM->>R: PUBLISH cmd-response:{imei} {result}
    end
    
    CM->>R: SET conn:{imei} = {...}
```

### PostgreSQL схема

```sql
-- Устройства
CREATE TABLE devices (
    id SERIAL PRIMARY KEY,
    imei VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(100),
    organization_id INTEGER REFERENCES organizations(id),
    device_type_id INTEGER REFERENCES device_types(id),
    protocol VARCHAR(20) NOT NULL,
    phone VARCHAR(20),
    vin VARCHAR(20),
    plate_number VARCHAR(20),
    icon VARCHAR(50) DEFAULT 'car',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ           -- soft delete
);

-- Типы устройств (модели трекеров)
CREATE TABLE device_types (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,       -- "Teltonika FMB920"
    protocol VARCHAR(20) NOT NULL,   -- "teltonika"
    commands JSONB,                  -- supported commands
    io_elements JSONB                -- IO element mapping
);

-- Журнал команд
CREATE TABLE command_log (
    id BIGSERIAL PRIMARY KEY,
    device_id INTEGER REFERENCES devices(id),
    command_type VARCHAR(50) NOT NULL,
    payload JSONB,
    status VARCHAR(20) NOT NULL,     -- pending, sent, executed, failed, timeout
    response JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_by INTEGER REFERENCES users(id)
);

CREATE INDEX idx_command_log_device ON command_log (device_id, created_at DESC);
CREATE INDEX idx_command_log_status ON command_log (status) WHERE status IN ('pending', 'sent');
```

### Redis структуры

```
# Очередь команд для offline устройств (ZSET по timestamp)
pending-cmd:{imei}
  score: timestamp
  member: {"id": 123, "type": "reboot", "payload": {...}}

# Pub/Sub каналы
cmd:{imei}           # команды к устройству
cmd-response:{imei}  # ответы от устройства

# Кеш конфигурации устройства
device:{imei}
  id: 123
  protocol: "teltonika"
  orgId: 456
  config: {...}
  TTL: 3600
```

### REST API

```yaml
# Device CRUD
GET    /api/v1/devices              # список устройств
GET    /api/v1/devices/{id}         # одно устройство
POST   /api/v1/devices              # создать
PUT    /api/v1/devices/{id}         # обновить
DELETE /api/v1/devices/{id}         # удалить (soft)

# Device position
GET    /api/v1/devices/{id}/position      # последняя позиция
GET    /api/v1/devices/{id}/track         # трек за период

# Commands
POST   /api/v1/devices/{id}/commands      # отправить команду
GET    /api/v1/devices/{id}/commands      # история команд
GET    /api/v1/commands/{id}              # статус команды

# Bulk operations
POST   /api/v1/devices/import             # массовый импорт
POST   /api/v1/devices/export             # экспорт в CSV
```

### Prometheus метрики

```
# Device operations
device_manager_operations_total{operation="create"} 150
device_manager_operations_total{operation="update"} 2400
device_manager_operations_total{operation="delete"} 45

# Commands
device_manager_commands_sent_total{type="reboot", status="success"} 1200
device_manager_commands_sent_total{type="reboot", status="queued"} 350
device_manager_commands_sent_total{type="reboot", status="timeout"} 23

# Pending queue
device_manager_pending_commands_total 156

# Cache
device_manager_cache_hits_total 450000
device_manager_cache_misses_total 1200
```

---

## 🔗 Взаимодействие сервисов Block 1

```mermaid
sequenceDiagram
    participant T as Трекер
    participant CM as Connection Manager
    participant DM as Device Manager
    participant HW as History Writer
    participant R as Redis
    participant K as Kafka
    participant DB as TimescaleDB

    Note over T,DB: Подключение и отправка данных
    
    T->>CM: TCP Connect + Login (IMEI)
    CM->>R: GET device:{imei}
    R-->>CM: Device config
    CM->>R: SET conn:{imei} = {...}
    CM-->>T: Login ACK

    loop GPS данные
        T->>CM: GPS packet
        CM->>CM: Parse & Filter
        CM->>R: SET pos:{imei} = {...}
        CM->>K: Publish gps-events
    end

    Note over K,DB: Асинхронная запись
    
    K->>HW: Poll messages
    HW->>HW: Batch aggregation
    HW->>DB: COPY gps_points

    Note over DM,T: Команды
    
    DM->>R: PUBLISH cmd:{imei}
    R-->>CM: Command notification
    CM->>T: Send command
    T-->>CM: Response
    CM->>R: PUBLISH cmd-response:{imei}
```

---

## 📊 Сводная таблица Block 1

| Параметр | Connection Manager | History Writer | Device Manager |
|----------|-------------------|----------------|----------------|
| **Тип** | TCP Server | Kafka Consumer | REST API |
| **Масштабирование** | Горизонтальное | Kafka partitions | Горизонтальное |
| **State** | Redis | Stateless | PostgreSQL |
| **Порты** | 5001-5004 | - | 8082 (internal) |
| **Критичность** | Высокая | Высокая | Средняя |
| **Latency target** | < 50ms | < 200ms | < 100ms |

---

## 🚀 Развёртывание

### Docker Compose (dev)

```yaml
services:
  connection-manager:
    build: ./services/connection-manager
    ports:
      - "5001:5001"
      - "5002:5002"
      - "5003:5003"
      - "5004:5004"
    environment:
      - KAFKA_BROKERS=kafka:9092
      - REDIS_URL=redis://redis:6379
    depends_on:
      - kafka
      - redis

  history-writer:
    build: ./services/history-writer
    environment:
      - KAFKA_BROKERS=kafka:9092
      - DATABASE_URL=postgresql://postgres:5432/tracker
    depends_on:
      - kafka
      - timescaledb

  device-manager:
    build: ./services/device-manager
    ports:
      - "8082:8082"
    environment:
      - DATABASE_URL=postgresql://postgres:5432/tracker
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis
```

---

**Дата:** 26 января 2026  
**Статус:** Block 1 документация готова ✅

**Следующий шаг:** [ARCHITECTURE_BLOCK2.md](./ARCHITECTURE_BLOCK2.md) — Бизнес-логика
