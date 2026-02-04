# 🤖 GitHub Copilot Instructions for Wayrecall Tracker

AI agents working on this codebase should understand these critical patterns and constraints.

## 🌍 Project Context

**Wayrecall Tracker** is a real-time GPS monitoring system for vehicle tracking. It's a microservices architecture handling 10,000+ trackers and 10,000 GPS points/sec with <100ms latency.

### Tech Stack
- **Language:** Scala 3.4.0
- **FX Runtime:** ZIO 2.0.20 (functional effects)
- **Messaging:** Apache Kafka 3.4+
- **Caching:** Redis 7.0
- **Storage:** TimescaleDB (timeseries), PostgreSQL (metadata)
- **Transport Protocols:** Teltonika, Wialon, Ruptela, NavTelecom (binary TCP)

## 🏗️ Service Architecture

**3 Core Services** (as git submodules):

```
services/
├── connection-manager    # TCP server listening ports 5001-5004
│                         # Parses binary protocols → Kafka gps-events
│
├── device-manager        # REST API on port 8092
│                         # CRUD devices, command queue (Redis), audit (Kafka)
│
└── history-writer        # Kafka consumer for gps-events
                          # Batches writes (500+ points) → TimescaleDB
```

**Data Flow:**
```
GPS Tracker (TCP)
    ↓
Connection Manager (parse + validate)
    ├→ Kafka: gps-events (stream)
    ├→ Kafka: device-status (online/offline)
    └→ Redis: device-status hash
         ↓
    History Writer (batch + hypertable insert)
         ↓
    REST API (queries via Device Manager)
```

## 🔑 Critical Patterns

### 1. ZIO Functional Effects (Required)

**NEVER use `var` or mutable state.** All effects go through ZIO monads.

```scala
// ✅ CORRECT: for comprehension, explicit error handling
def parseGpsMessage(raw: ByteBuffer): Task[GpsEvent] = for {
  // Monadic chain with error propagation
  protocol <- identifyProtocol(raw)
  parsed   <- protocol.parse(raw).mapError(ParseError(_))
  event    <- validateEvent(parsed)
  _        <- ZIO.logDebug(s"Parsed event: ${event.imei}")
} yield event

// ❌ WRONG: mutable variables, blocking calls
def parseGpsMessage(raw: ByteBuffer): GpsEvent = {
  var protocol = identifyProtocol(raw)  // var = forbidden
  val parsed = protocol.parse(raw).get  // unsafe .get()
  parsed.event
}
```

### 2. Multi-Tenant Isolation (MUST)

Every query must filter by `organization_id`. Use sealed service boundaries:

```scala
// ✅ CORRECT: explicit organization context
def getDevices(orgId: Long): Task[List[Device]] =
  repository.findByOrganization(orgId)  // Organization in query

// ❌ WRONG: forgetting organization filter
def getDevices(): Task[List[Device]] =
  repository.findAll()  // Leaks data across orgs!
```

### 3. Kafka Partitioning (for Ordering)

- **gps-events topic:** Partitioned by `deviceId` (preserves per-device order)
- **device-status topic:** Partitioned by `imei`
- **command-audit topic:** Partitioned by `deviceId`

Commands on same device must order correctly (use same partition key).

### 4. Redis as Distributed Cache + Queue

```
Device Cache:           device:{id} = Device JSON (TTL: 5min)
Device Status:          device:{id}:status = DeviceStatus
Command Queue:          pending_commands:{imei} = ZSET (TTL: 24h)
Connection Registry:    connection_registry = HSET (device_id → instance_id)
```

The Connection Manager writes status; Device Manager reads + writes commands.

### 5. Error Types (Typed Errors Required)

```scala
// ✅ Create sealed error hierarchy, never throw unchecked exceptions
sealed trait DomainError extends Throwable:
  def message: String

case class DeviceNotFound(id: Long) extends DomainError:
  def message = s"Device $id not found"

case class InvalidImei(imei: String) extends DomainError:
  def message = s"Invalid IMEI format: $imei"

// Use in code:
def getDevice(id: Long): Task[Device] =
  repository.findById(id).someOrFail(DeviceNotFound(id))
```

## 📐 Code Organization

### Package Structure
```
src/main/scala/tracergps/{serviceName}/
├── api/          # HTTP handlers (ZIO HTTP routes)
├── service/      # Business logic (pure functions + ZIO)
├── repository/   # Database operations (Doobie)
├── config/       # Configuration (zio-config)
├── domain/       # Sealed traits, case classes
└── util/         # Helpers (validation, parsing)
```

### Database Pattern (Doobie)

```scala
// ✅ CORRECT: defer effects to Task, pure mapping
def findById(id: Long): Task[Option[Device]] =
  task(sql"SELECT * FROM devices WHERE id = $id".query[Device].option)

// All DB ops return Task[T], not blocking synchronously
```

### REST API Pattern (ZIO HTTP)

```scala
// ✅ Collect routes via handler functions
def routes: Routes[DeviceService, Response] =
  Routes(
    Method.GET / "api" / "v1" / "devices" -> 
      handler { (req: Request) =>
        for {
          auth <- ZIO.service[AuthContext]
          page <- req.queryParams.decode[Page]
          result <- ZIO.serviceWithZIO[DeviceService](
            _.listByOrganization(auth.orgId, page)
          )
        } yield Response.json(result.toJson)
      },
    
    Method.POST / "api" / "v1" / "devices" ->
      handler { (req: Request) =>
        for {
          auth <- ZIO.service[AuthContext]
          body <- req.body.asJson[CreateDeviceRequest]
          device <- ZIO.serviceWithZIO[DeviceService](
            _.create(auth.orgId, body)
          )
        } yield Response.json(device.toJson).status(Status.Created)
      }
  )
```

## 🧪 Testing Requirements

- **Service layer:** 80%+ unit test coverage (use `ZIOSpecDefault`)
- **Database layer:** Integration tests with `testcontainers-postgresql`
- **Mocking:** Use `Mock` from ZIO Test for dependencies

```scala
class DeviceServiceSpec extends ZIOSpecDefault:
  def spec = suite("DeviceService")(
    test("create device with valid IMEI") {
      for {
        service <- ZIO.service[DeviceService]
        device  <- service.create(
          orgId = 1,
          CreateDeviceRequest(imei = "860719020025346", name = "Truck-001")
        )
      } yield assertTrue(device.imei == "860719020025346")
    }
  ).provide(...)
```

## ⚠️ Common Mistakes to Avoid

| Mistake | Impact | Fix |
|---------|--------|-----|
| Using `.get` on Option/Try | Runtime crashes | Use `someOrFail()` or pattern match |
| Forgetting `organization_id` filter | Data leak | Always check service for org context |
| `var` instead of `val` | Breaks referential transparency | Use immutable collections |
| Blocking calls in effects | Deadlocks | Use non-blocking APIs (ZIO, async) |
| String partition keys in Kafka | Wrong ordering | Use numeric `deviceId` for partition |
| Null returns from DB | NPE at runtime | Use Option/Either in schema |
| Ignoring Kafka message ordering | Command race conditions | Same device on same partition |

## 📖 Essential Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** – High-level design, data flows
- **[docs/ARCHITECTURE_BLOCK1.md](docs/ARCHITECTURE_BLOCK1.md)** – Connection Manager + History Writer detail
- **[docs/services/DEVICE_MANAGER.md](docs/services/DEVICE_MANAGER.md)** – REST API, commands, PostgreSQL schema
- **[docs/DATA_STORES.md](docs/DATA_STORES.md)** – Redis structure, TimescaleDB tables
- **[docs/AI_AGENTS_INSTRUCTIONS.md](docs/AI_AGENTS_INSTRUCTIONS.md)** – FP rules, Scala best practices

## 🚀 Development Workflow

```bash
# Compile all services
sbt compile

# Run specific service
sbt "project connection-manager" run

# Test
sbt test
sbt "project device-manager" testOnly *.ServiceSpec

# Docker local infra
docker-compose up -d

# Submodules are git references—pull changes with:
git submodule update --init --recursive
```

## 🎯 Before Writing Code

1. **Understand service boundaries** – does your change cross services? (Then use Kafka/Redis)
2. **Check org isolation** – is `organization_id` enforced in queries?
3. **Review Kafka topics** – which topic should this event go to?
4. **Test error cases** – what happens if device is offline, DB fails, Redis is down?
5. **Document data flows** – where does this data come from/go to?

## 🗣️ Communication Rules

- **Always respond in Russian** (документация, комментарии, обсуждение)
- **All code comments in Russian** – explain business logic, not obvious syntax
- **Confirm understanding before coding** – ask clarifying questions
- **Break large tasks into steps** – show progress incrementally
- **Request feedback after each section** – iterate based on response

---

## 🔧 Functional Programming Principles (ULTRA FP MODE)

### 1. Immutability (MUST)
- Never use `var` – only `val`
- Use case classes for data, sealed traits for types
- Immutable collections (List, Map, Set)

### 2. Pure Functions
- No side effects (no printing, no mutations)
- Deterministic (same input = same output)
- All effects must go through ZIO monads

### 3. Error Handling
```scala
// ✅ Typed errors (never throw exceptions)
sealed trait AppError extends Throwable
case class DeviceNotFound(id: Long) extends AppError

// Use Either/Option for error paths
def getDevice(id: Long): Task[Device] =
  repository.findById(id).someOrFail(DeviceNotFound(id))
```

### 4. Type Safety
- Explicit types for all parameters and returns
- Use opaque types for domain values (IMEI, OrganizationId)
- Let compiler catch errors, not runtime

### 5. Composition Over Inheritance
- Use trait composition for behavior
- Leverage ZIO environment for dependency injection
- Avoid tight coupling between services

---

## 📋 Code Patterns by Layer

### Service Layer (Business Logic)
```scala
// Pure functions wrapped in ZIO
def processDevice(id: Long): Task[Device] = for {
  device <- repository.findById(id).someOrFail(DeviceNotFound(id))
  validated <- validateDevice(device)
  _ <- logAction(s"Processing device $id")
} yield validated
```

### API Layer (HTTP Handlers)
```scala
// Always validate, handle errors, return proper status codes
def routes: Routes[DeviceService, Response] =
  Routes(
    Method.GET / "api" / "v1" / "devices" -> handler { req =>
      for {
        auth <- ZIO.service[AuthContext]
        result <- ZIO.serviceWithZIO[DeviceService](_.listByOrganization(auth.orgId))
      } yield Response.json(result.toJson)
    }
  )
```

### Repository Layer (Data Access)
```scala
// Always return Task[Option[T]], not raw DB values
def findById(id: Long): Task[Option[Device]] =
  task(sql"SELECT * FROM devices WHERE id = $id".query[Device].option)
```

---

## ⚠️ Language-Specific Rules for Scala

### Naming Conventions
- `camelCase` for methods and variables
- `PascalCase` for classes and traits
- `SCREAMING_SNAKE_CASE` for constants
- Prefix with `_` for unused parameters

### Pattern Matching
- Use exhaustive matching (compiler will warn about missing cases)
- Prefer pattern matching over if-else

### Comments & Documentation
```scala
// ✅ Scaladoc for public API
/** 
  * Получить устройство по ID.
  * @param id ID устройства
  * @return Task с опциональным устройством
  */
def findDevice(id: Long): Task[Option[Device]]

// ✅ Explain WHY, not WHAT (code explains what)
// Фильтруем точки < 10м друг от друга (GPS шум)
val filtered = locations.sliding(2)
  .filter { case Seq(a, b) => distance(a, b) > 10.0 }
```

---

## 📊 Data Store Patterns

### Redis Keys (Cache + Queue + Pub/Sub)
```
device:{id}                  = Device JSON (cache, TTL 5min)
device:imei:{imei}          = device_id (lookup)
pending_commands:{imei}     = ZSET (queue for offline devices, TTL 24h)
device:{id}:status          = DeviceStatus JSON
connection_registry         = HSET (device_id → cm_instance_id)
```

### Kafka Topics (with Partition Keys)
| Topic | Partition Key | Purpose |
|-------|---------------|---------|
| `gps-events` | `deviceId` | GPS positions from trackers |
| `device-status` | `imei` | Online/offline events |
| `command-audit` | `deviceId` | Command history (ordered per device) |

### TimescaleDB Hypertables
- `device_positions` – partitioned by time and deviceId
- Automatic compression + downsampling for old data
- Queries use `time_bucket` for efficient aggregation

---

## 🧪 Testing Checklist

Before submitting code:
- [ ] Unit tests cover service layer (>80%)
- [ ] Test happy path + error scenarios
- [ ] Integration tests for DB/Redis/Kafka
- [ ] Use ZIOSpecDefault for async tests
- [ ] Mock external dependencies with ZIO Mock
- [ ] No hardcoded secrets in tests

---

## 📚 Key Documentation Files

| File | Purpose |
|------|---------|
| `docs/ARCHITECTURE.md` | System overview, data flows, components |
| `docs/ARCHITECTURE_BLOCK1.md` | Connection Manager + History Writer |
| `docs/services/DEVICE_MANAGER.md` | REST API, commands, PostgreSQL schema |
| `docs/DATA_STORES.md` | Redis structure, TimescaleDB design |
| `docs/AI_AGENTS_INSTRUCTIONS.md` | Detailed FP rules, code examples, patterns |

---

## 🚀 Common Commands

```bash
# Compile all services
sbt compile

# Run single service
sbt "project connection-manager" run

# Run tests
sbt test
sbt "project device-manager" testOnly *.ServiceSpec

# Update submodules
git submodule update --init --recursive

# Start local infrastructure
docker-compose up -d
docker-compose down
```

---

**Version:** 2.0  
**Updated:** 26 января 2026  
**Maintained by:** Development Team  
**Related:** `docs/AI_AGENTS_INSTRUCTIONS.md` (detailed guide with examples)
