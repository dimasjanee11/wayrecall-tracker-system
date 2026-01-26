# API Gateway

> Блок 3 | Презентация | Приоритет: MVP

## Обзор

Единая точка входа для всех REST API запросов. Маршрутизация, аутентификация, rate limiting, агрегация ответов.

## Характеристики

| Параметр | Значение |
|----------|----------|
| Порт | 8080 (HTTP), 8443 (HTTPS) |
| Язык | Scala 3 + ZIO |
| Аутентификация | JWT + API Key |
| Rate Limiting | Redis-based |
| Service Discovery | Static / Consul |

---

## 1. Архитектура

### 1.1 Mermaid Диаграмма - Общая архитектура

```mermaid
graph TB
    subgraph "Клиенты"
        WEB[Web Frontend]
        MOBILE[Mobile App]
        EXT[External API]
    end

    subgraph "API Gateway :8080"
        subgraph "Входной слой"
            LB[Load Balancer<br/>nginx/envoy]
            TLS[TLS Termination]
        end
        
        subgraph "Middleware Pipeline"
            CORS[CORS Handler]
            LOG[Request Logger]
            RATE[Rate Limiter]
            AUTH[Auth Middleware]
            VALID[Request Validator]
        end
        
        subgraph "Маршрутизация"
            ROUTER[Router<br/>Path Matcher]
            AGG[Response Aggregator]
            CACHE[Response Cache]
        end
    end

    subgraph "Backend Services"
        DEVICE[Device Manager<br/>:8083]
        GEO[Geozones Service<br/>:8084]
        NOTIF[Notifications<br/>:8085]
        ANAL[Analytics<br/>:8086]
        MAINT[Maintenance<br/>:8087]
        USER[User Service<br/>:8091]
        AUTHSVC[Auth Service<br/>:8092]
    end

    subgraph "Хранилище"
        REDIS[(Redis<br/>Rate Limits<br/>Cache)]
    end

    WEB --> LB
    MOBILE --> LB
    EXT --> LB
    
    LB --> TLS
    TLS --> CORS
    CORS --> LOG
    LOG --> RATE
    RATE --> AUTH
    AUTH --> VALID
    VALID --> ROUTER
    
    ROUTER --> DEVICE
    ROUTER --> GEO
    ROUTER --> NOTIF
    ROUTER --> ANAL
    ROUTER --> MAINT
    ROUTER --> USER
    ROUTER --> AUTHSVC
    
    RATE --> REDIS
    AUTH --> REDIS
    CACHE --> REDIS
    
    AGG --> ROUTER

    style LB fill:#e1f5fe
    style AUTH fill:#fff3e0
    style RATE fill:#ffebee
    style ROUTER fill:#c8e6c9
```

### 1.2 UML Sequence - Аутентифицированный запрос

```
┌────────┐  ┌──────────┐  ┌────────┐  ┌──────────┐  ┌────────┐  ┌─────────┐  ┌──────────┐
│ Client │  │   TLS    │  │  Rate  │  │   Auth   │  │ Router │  │ Backend │  │  Redis   │
│        │  │Terminator│  │ Limiter│  │Middleware│  │        │  │ Service │  │          │
└───┬────┘  └────┬─────┘  └───┬────┘  └────┬─────┘  └───┬────┘  └────┬────┘  └────┬─────┘
    │            │            │            │            │            │            │
    │ HTTPS Request           │            │            │            │            │
    │───────────>│            │            │            │            │            │
    │            │            │            │            │            │            │
    │            │ HTTP Request            │            │            │            │
    │            │───────────>│            │            │            │            │
    │            │            │            │            │            │            │
    │            │            │ INCR rate:{ip}          │            │            │
    │            │            │─────────────────────────────────────────────────>│
    │            │            │            │            │            │            │
    │            │            │  count < limit          │            │            │
    │            │            │<─────────────────────────────────────────────────│
    │            │            │            │            │            │            │
    │            │            │ pass       │            │            │            │
    │            │            │───────────>│            │            │            │
    │            │            │            │            │            │            │
    │            │            │            │ GET session:{token}     │            │
    │            │            │            │────────────────────────────────────>│
    │            │            │            │            │            │            │
    │            │            │            │   user context          │            │
    │            │            │            │<────────────────────────────────────│
    │            │            │            │            │            │            │
    │            │            │            │ validateJWT()           │            │
    │            │            │            │──────┐    │            │            │
    │            │            │            │      │    │            │            │
    │            │            │            │<─────┘    │            │            │
    │            │            │            │            │            │            │
    │            │            │            │ route(path, method)     │            │
    │            │            │            │───────────>│            │            │
    │            │            │            │            │            │            │
    │            │            │            │            │ forward request         │
    │            │            │            │            │───────────>│            │
    │            │            │            │            │            │            │
    │            │            │            │            │  response  │            │
    │            │            │            │            │<───────────│            │
    │            │            │            │            │            │            │
    │            │            │  response  │            │            │            │
    │<────────────────────────────────────────────────────────────────            │
    │            │            │            │            │            │            │
```

### 1.3 UML Sequence - Rate Limiting с блокировкой

```
┌────────┐  ┌────────┐  ┌──────────┐  ┌────────┐
│ Client │  │  Rate  │  │  Redis   │  │  Log   │
│        │  │ Limiter│  │          │  │        │
└───┬────┘  └───┬────┘  └────┬─────┘  └───┬────┘
    │           │            │            │
    │ Request   │            │            │
    │──────────>│            │            │
    │           │            │            │
    │           │ MULTI      │            │
    │           │───────────>│            │
    │           │            │            │
    │           │ INCR rate:limit:{key}   │
    │           │───────────>│            │
    │           │            │            │
    │           │ EXPIRE {key} {window}   │
    │           │───────────>│            │
    │           │            │            │
    │           │ EXEC       │            │
    │           │───────────>│            │
    │           │            │            │
    │           │ [count, ttl]│            │
    │           │<───────────│            │
    │           │            │            │
    │           │            │            │
    │           ├─────────── count > limit?
    │           │            │            │
    │           │            │            │
    │    ┌──────┴──────┐     │            │
    │    │    YES      │     │            │
    │    └──────┬──────┘     │            │
    │           │            │            │
    │           │ logRateLimitExceeded()  │
    │           │───────────────────────>│
    │           │            │            │
    │ 429 Too Many           │            │
    │ Retry-After: {ttl}     │            │
    │<──────────│            │            │
    │           │            │            │
    │    ┌──────┴──────┐     │            │
    │    │    NO       │     │            │
    │    └──────┬──────┘     │            │
    │           │            │            │
    │ X-RateLimit-Remaining  │            │
    │<──────────│ (continue) │            │
    │           │            │            │
```

### 1.4 UML Sequence - Агрегация ответов (Dashboard)

```
┌────────┐  ┌─────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐
│ Client │  │ Gateway │  │  Device  │  │ Geozones   │  │Analytics │  │Maintenance│
│        │  │  (Agg)  │  │  Manager │  │  Service   │  │ Service  │  │ Service  │
└───┬────┘  └────┬────┘  └────┬─────┘  └─────┬──────┘  └────┬─────┘  └────┬─────┘
    │            │            │              │              │              │
    │ GET /api/v1/dashboard   │              │              │              │
    │───────────>│            │              │              │              │
    │            │            │              │              │              │
    │            │ parallel requests        │              │              │
    │            ├───────────────────────────────────────────────────────────┐
    │            │            │              │              │              │ │
    │            │ GET /vehicles/summary    │              │              │ │
    │            │───────────>│              │              │              │ │
    │            │            │              │              │              │ │
    │            │ GET /geozones/events/recent              │              │ │
    │            │───────────────────────────>│              │              │ │
    │            │            │              │              │              │ │
    │            │ GET /analytics/summary   │              │              │ │
    │            │─────────────────────────────────────────>│              │ │
    │            │            │              │              │              │ │
    │            │ GET /maintenance/overview│              │              │ │
    │            │───────────────────────────────────────────────────────>│ │
    │            │            │              │              │              │ │
    │            │  vehicles  │              │              │              │ │
    │            │<───────────│              │              │              │ │
    │            │            │              │              │              │ │
    │            │            │ geoEvents   │              │              │ │
    │            │<───────────────────────────│              │              │ │
    │            │            │              │              │              │ │
    │            │            │   analytics │              │              │ │
    │            │<─────────────────────────────────────────│              │ │
    │            │            │              │              │              │ │
    │            │            │              │  maintenance │              │ │
    │            │<───────────────────────────────────────────────────────│ │
    │            ├───────────────────────────────────────────────────────────┘
    │            │            │              │              │              │
    │            │ aggregateResponses()     │              │              │
    │            │──────┐    │              │              │              │
    │            │      │    │              │              │              │
    │            │<─────┘    │              │              │              │
    │            │            │              │              │              │
    │ Dashboard  │            │              │              │              │
    │ Response   │            │              │              │              │
    │<───────────│            │              │              │              │
    │            │            │              │              │              │
```

---

## 2. Модели данных

### 2.1 Scala модели

```scala
package tracker.gateway.domain

import java.time.Instant
import java.util.UUID

// ============================================
// Конфигурация маршрутов
// ============================================

/** Конфигурация backend сервиса */
final case class ServiceConfig(
  name: String,                          // "device-manager"
  baseUrl: String,                       // "http://device-manager:8083"
  healthPath: String,                    // "/health"
  timeout: Duration,                     // 30.seconds
  retries: Int,                          // 3
  circuitBreaker: CircuitBreakerConfig
)

final case class CircuitBreakerConfig(
  failureThreshold: Int,                 // 5 ошибок
  resetTimeout: Duration,                // 30.seconds
  halfOpenRequests: Int                  // 3 запроса в half-open
)

/** Правило маршрутизации */
final case class RouteRule(
  id: String,
  pathPattern: String,                   // "/api/v1/devices/**"
  methods: Set[HttpMethod],              // GET, POST, PUT, DELETE
  targetService: String,                 // "device-manager"
  stripPrefix: Option[String],           // "/api/v1"
  addPrefix: Option[String],             // "/internal"
  requiresAuth: Boolean,
  requiredRoles: Set[String],            // ["admin", "user"]
  rateLimit: Option[RateLimitConfig],
  cacheConfig: Option[CacheConfig]
)

// ============================================
// Rate Limiting
// ============================================

/** Конфигурация rate limiting */
final case class RateLimitConfig(
  requestsPerWindow: Int,                // 100 запросов
  windowSize: Duration,                  // 1.minute
  keyExtractor: RateLimitKey,            // IP, User, ApiKey
  burstSize: Option[Int]                 // превышение для burst
)

/** Ключ для rate limiting */
enum RateLimitKey:
  case ByIp                              // по IP адресу
  case ByUser                            // по userId
  case ByApiKey                          // по API ключу
  case ByEndpoint                        // по endpoint
  case Combined(keys: List[RateLimitKey])// комбинация

/** Результат проверки лимита */
final case class RateLimitResult(
  allowed: Boolean,
  remaining: Int,                        // осталось запросов
  resetAt: Instant,                      // когда сбросится
  retryAfter: Option[Duration]           // через сколько повторить
)

// ============================================
// Аутентификация
// ============================================

/** Контекст пользователя после аутентификации */
final case class UserContext(
  userId: UUID,
  companyId: UUID,
  email: String,
  roles: Set[String],                    // ["admin", "user", "viewer"]
  permissions: Set[String],              // ["devices:read", "devices:write"]
  sessionId: UUID,
  tokenExpiry: Instant,
  metadata: Map[String, String]          // дополнительные данные
)

/** API Key для внешних интеграций */
final case class ApiKeyContext(
  keyId: UUID,
  companyId: UUID,
  name: String,
  permissions: Set[String],
  rateLimit: RateLimitConfig,
  expiresAt: Option[Instant]
)

/** Результат аутентификации */
enum AuthResult:
  case Authenticated(context: UserContext)
  case ApiKeyAuth(context: ApiKeyContext)
  case Anonymous
  case Failed(reason: String)

// ============================================
// Запросы и ответы
// ============================================

/** Обогащённый запрос */
final case class GatewayRequest(
  id: UUID,                              // request ID для трейсинга
  method: HttpMethod,
  path: String,
  query: Map[String, String],
  headers: Map[String, String],
  body: Option[Array[Byte]],
  clientIp: String,
  receivedAt: Instant,
  authResult: AuthResult
)

/** Ответ от backend */
final case class BackendResponse(
  statusCode: Int,
  headers: Map[String, String],
  body: Option[Array[Byte]],
  serviceName: String,
  duration: Duration
)

/** Ответ Gateway */
final case class GatewayResponse(
  statusCode: Int,
  headers: Map[String, String],
  body: Option[Array[Byte]],
  requestId: UUID
)

// ============================================
// Кэширование
// ============================================

/** Конфигурация кэширования */
final case class CacheConfig(
  ttl: Duration,                         // время жизни в кэше
  varyBy: List[String],                  // заголовки для vary
  cacheKey: Option[String]               // кастомный ключ
)

/** Кэшированный ответ */
final case class CachedResponse(
  response: GatewayResponse,
  cachedAt: Instant,
  expiresAt: Instant,
  etag: String
)

// ============================================
// Health и метрики
// ============================================

/** Состояние backend сервиса */
final case class ServiceHealth(
  name: String,
  status: HealthStatus,
  lastCheck: Instant,
  latency: Duration,
  errorRate: Double
)

enum HealthStatus:
  case Healthy
  case Degraded
  case Unhealthy
  case Unknown

/** Агрегированный статус */
final case class GatewayHealth(
  status: HealthStatus,
  services: List[ServiceHealth],
  uptime: Duration,
  requestsPerSecond: Double
)

// ============================================
// Агрегация
// ============================================

/** Dashboard агрегация */
final case class DashboardResponse(
  vehiclesSummary: VehiclesSummary,
  recentGeoEvents: List[GeoEventSummary],
  analyticsSnapshot: AnalyticsSnapshot,
  maintenanceOverview: MaintenanceOverview,
  timestamp: Instant
)

final case class VehiclesSummary(
  total: Int,
  online: Int,
  moving: Int,
  stopped: Int,
  offline: Int
)

final case class GeoEventSummary(
  vehicleId: UUID,
  vehicleName: String,
  eventType: String,
  geozoneName: String,
  timestamp: Instant
)

final case class AnalyticsSnapshot(
  totalDistanceToday: Long,
  totalTrips: Int,
  averageSpeed: Double,
  fuelUsed: Double
)

final case class MaintenanceOverview(
  overdueCount: Int,
  upcomingCount: Int,
  completedThisMonth: Int
)

// ============================================
// Ошибки
// ============================================

enum GatewayError:
  case Unauthorized(message: String)
  case Forbidden(message: String, requiredRoles: Set[String])
  case RateLimitExceeded(retryAfter: Duration)
  case ServiceUnavailable(serviceName: String)
  case BadGateway(serviceName: String, cause: String)
  case RouteNotFound(path: String)
  case RequestTimeout(serviceName: String, timeout: Duration)
  case ValidationError(errors: List[String])
```

---

## 3. Конфигурация маршрутов

### 3.1 YAML конфигурация

```yaml
# gateway-routes.yaml

services:
  - name: auth-service
    baseUrl: http://auth-service:8092
    healthPath: /health
    timeout: 10s
    retries: 2
    circuitBreaker:
      failureThreshold: 5
      resetTimeout: 30s
      halfOpenRequests: 3

  - name: user-service
    baseUrl: http://user-service:8091
    healthPath: /health
    timeout: 15s
    retries: 3

  - name: device-manager
    baseUrl: http://device-manager:8083
    healthPath: /health
    timeout: 30s
    retries: 3

  - name: geozones-service
    baseUrl: http://geozones-service:8084
    healthPath: /health
    timeout: 20s
    retries: 3

  - name: notifications-service
    baseUrl: http://notifications-service:8085
    healthPath: /health
    timeout: 15s
    retries: 2

  - name: analytics-service
    baseUrl: http://analytics-service:8086
    healthPath: /health
    timeout: 60s
    retries: 2

  - name: maintenance-service
    baseUrl: http://maintenance-service:8087
    healthPath: /health
    timeout: 30s
    retries: 3

routes:
  # ========================================
  # Auth (публичные endpoints)
  # ========================================
  - id: auth-login
    pathPattern: /api/v1/auth/login
    methods: [POST]
    targetService: auth-service
    requiresAuth: false
    rateLimit:
      requestsPerWindow: 10
      windowSize: 1m
      keyExtractor: ByIp

  - id: auth-refresh
    pathPattern: /api/v1/auth/refresh
    methods: [POST]
    targetService: auth-service
    requiresAuth: false
    rateLimit:
      requestsPerWindow: 30
      windowSize: 1m
      keyExtractor: ByIp

  - id: auth-register
    pathPattern: /api/v1/auth/register
    methods: [POST]
    targetService: auth-service
    requiresAuth: false
    rateLimit:
      requestsPerWindow: 5
      windowSize: 1h
      keyExtractor: ByIp

  # ========================================
  # User Service
  # ========================================
  - id: user-profile
    pathPattern: /api/v1/users/me
    methods: [GET, PUT]
    targetService: user-service
    requiresAuth: true
    
  - id: user-management
    pathPattern: /api/v1/users/**
    methods: [GET, POST, PUT, DELETE]
    targetService: user-service
    requiresAuth: true
    requiredRoles: [admin]

  # ========================================
  # Device Manager
  # ========================================
  - id: devices-list
    pathPattern: /api/v1/devices
    methods: [GET]
    targetService: device-manager
    requiresAuth: true
    cacheConfig:
      ttl: 30s
      varyBy: [Authorization]

  - id: devices-crud
    pathPattern: /api/v1/devices/**
    methods: [GET, POST, PUT, DELETE]
    targetService: device-manager
    requiresAuth: true
    
  - id: vehicles-crud
    pathPattern: /api/v1/vehicles/**
    methods: [GET, POST, PUT, DELETE]
    targetService: device-manager
    requiresAuth: true

  # ========================================
  # Geozones Service
  # ========================================
  - id: geozones-crud
    pathPattern: /api/v1/geozones/**
    methods: [GET, POST, PUT, DELETE]
    targetService: geozones-service
    requiresAuth: true

  # ========================================
  # Notifications Service
  # ========================================
  - id: notifications-crud
    pathPattern: /api/v1/notifications/**
    methods: [GET, POST, PUT, DELETE]
    targetService: notifications-service
    requiresAuth: true

  # ========================================
  # Analytics Service
  # ========================================
  - id: analytics-reports
    pathPattern: /api/v1/analytics/**
    methods: [GET, POST]
    targetService: analytics-service
    requiresAuth: true
    timeout: 60s  # длинные отчёты

  # ========================================
  # Maintenance Service
  # ========================================
  - id: maintenance-crud
    pathPattern: /api/v1/maintenance/**
    methods: [GET, POST, PUT, DELETE]
    targetService: maintenance-service
    requiresAuth: true

  # ========================================
  # Aggregated Endpoints
  # ========================================
  - id: dashboard
    pathPattern: /api/v1/dashboard
    methods: [GET]
    targetService: _aggregate_
    requiresAuth: true
    aggregation:
      parallel: true
      timeout: 5s
      endpoints:
        - service: device-manager
          path: /vehicles/summary
          field: vehiclesSummary
        - service: geozones-service
          path: /events/recent?limit=10
          field: recentGeoEvents
        - service: analytics-service
          path: /summary/today
          field: analyticsSnapshot
        - service: maintenance-service
          path: /overview
          field: maintenanceOverview

# Глобальные настройки
global:
  defaultRateLimit:
    requestsPerWindow: 1000
    windowSize: 1m
    keyExtractor: ByUser
    
  cors:
    allowedOrigins:
      - https://tracker.example.com
      - http://localhost:3000
    allowedMethods: [GET, POST, PUT, DELETE, OPTIONS]
    allowedHeaders: [Authorization, Content-Type, X-Request-ID]
    maxAge: 3600
    
  security:
    jwtSecret: ${JWT_SECRET}
    jwtIssuer: tracker-auth
    tokenExpiry: 24h
```

---

## 4. Redis структуры

```yaml
# ==========================================
# Rate Limiting
# ==========================================

# Счётчик запросов по IP
key: "gateway:rate:ip:{clientIp}:{window}"
value: "count"  # integer
ttl: {windowSize}

# Счётчик запросов по пользователю
key: "gateway:rate:user:{userId}:{window}"
value: "count"
ttl: {windowSize}

# Счётчик запросов по API ключу
key: "gateway:rate:apikey:{keyId}:{window}"
value: "count"
ttl: {windowSize}

# Блокировка при превышении (для burst protection)
key: "gateway:blocked:{keyType}:{keyValue}"
value: "1"
ttl: 60s  # время блокировки

# ==========================================
# Сессии и токены
# ==========================================

# Сессия пользователя (кэш JWT claims)
key: "gateway:session:{sessionId}"
value: |
  {
    "userId": "uuid",
    "companyId": "uuid",
    "email": "user@example.com",
    "roles": ["admin", "user"],
    "permissions": ["devices:read", "devices:write"],
    "tokenExpiry": "2025-01-21T12:00:00Z"
  }
ttl: 3600s  # 1 час или до истечения токена

# Чёрный список токенов (после logout)
key: "gateway:blacklist:token:{jti}"
value: "1"
ttl: {до истечения токена}

# API ключи
key: "gateway:apikey:{keyHash}"
value: |
  {
    "keyId": "uuid",
    "companyId": "uuid",
    "name": "Integration Key",
    "permissions": ["devices:read"],
    "rateLimit": {...}
  }
ttl: -  # без TTL, управляется явно

# ==========================================
# Response Cache
# ==========================================

# Кэшированный ответ
key: "gateway:cache:{cacheKey}"
value: |
  {
    "statusCode": 200,
    "headers": {...},
    "body": "base64...",
    "etag": "abc123",
    "cachedAt": "2025-01-20T10:00:00Z"
  }
ttl: {cacheConfig.ttl}

# ==========================================
# Circuit Breaker State
# ==========================================

# Состояние circuit breaker для сервиса
key: "gateway:circuit:{serviceName}"
value: |
  {
    "state": "closed|open|half_open",
    "failures": 0,
    "lastFailure": "2025-01-20T10:00:00Z",
    "openedAt": null
  }
ttl: -

# ==========================================
# Service Health
# ==========================================

# Последний health check
key: "gateway:health:{serviceName}"
value: |
  {
    "status": "healthy",
    "lastCheck": "2025-01-20T10:00:00Z",
    "latency": 45,
    "errorRate": 0.01
  }
ttl: 30s
```

---

## 5. REST API Gateway Endpoints

### 5.1 Системные endpoints

```yaml
# ==========================================
# Health & Metrics
# ==========================================

# Health check
GET /health
Response: 200 OK
  {
    "status": "healthy",
    "services": [
      {"name": "device-manager", "status": "healthy", "latency": 45},
      {"name": "auth-service", "status": "healthy", "latency": 12}
    ],
    "uptime": "5d 12h 30m"
  }

# Ready check (для k8s)
GET /ready
Response: 200 OK / 503 Service Unavailable

# Prometheus metrics
GET /metrics
Response: 200 OK (text/plain)

# ==========================================
# API Documentation
# ==========================================

# OpenAPI spec
GET /api/v1/openapi.json
Response: 200 OK
  { OpenAPI 3.0 specification }

# Swagger UI
GET /api/docs
Response: 200 OK (HTML)
```

### 5.2 Стандартные заголовки ответов

```yaml
# Все ответы включают:
X-Request-ID: {uuid}                     # ID запроса для трейсинга
X-Response-Time: {ms}                    # Время обработки

# Rate limiting заголовки:
X-RateLimit-Limit: 1000                  # Лимит запросов
X-RateLimit-Remaining: 950               # Осталось запросов
X-RateLimit-Reset: 1705750800            # Unix timestamp сброса

# При превышении лимита (429):
Retry-After: 60                          # Секунд до повтора

# CORS заголовки:
Access-Control-Allow-Origin: https://tracker.example.com
Access-Control-Allow-Methods: GET, POST, PUT, DELETE
Access-Control-Allow-Headers: Authorization, Content-Type
Access-Control-Max-Age: 3600

# Кэширование:
ETag: "abc123"
Cache-Control: private, max-age=30
```

---

## 6. Middleware Pipeline

### 6.1 Scala реализация pipeline

```scala
package tracker.gateway.middleware

import zio._

// Тип middleware
type Middleware = GatewayRequest => ZIO[Any, GatewayError, GatewayRequest]

// Композиция middleware
object MiddlewarePipeline:
  
  def apply(middlewares: List[Middleware]): Middleware =
    request => ZIO.foldLeft(middlewares)(request) { (req, middleware) =>
      middleware(req)
    }

  val standard: Middleware = apply(List(
    CorsMiddleware.handle,
    RequestIdMiddleware.handle,
    LoggingMiddleware.handle,
    RateLimitMiddleware.handle,
    AuthMiddleware.handle,
    ValidationMiddleware.handle
  ))

// CORS Middleware
object CorsMiddleware:
  def handle(config: CorsConfig): Middleware = request =>
    if request.method == HttpMethod.OPTIONS then
      ZIO.fail(GatewayError.CorsPreflightResponse(config))
    else
      ZIO.succeed(request)

// Request ID Middleware
object RequestIdMiddleware:
  def handle: Middleware = request =>
    val requestId = request.headers.get("X-Request-ID")
      .map(UUID.fromString)
      .getOrElse(UUID.randomUUID())
    ZIO.succeed(request.copy(id = requestId))

// Logging Middleware
object LoggingMiddleware:
  def handle: Middleware = request =>
    ZIO.logInfo(s"${request.method} ${request.path} from ${request.clientIp}") *>
    ZIO.succeed(request)

// Rate Limit Middleware
object RateLimitMiddleware:
  def handle(limiter: RateLimiter): Middleware = request =>
    limiter.check(request).flatMap {
      case RateLimitResult(false, _, _, Some(retryAfter)) =>
        ZIO.fail(GatewayError.RateLimitExceeded(retryAfter))
      case _ =>
        ZIO.succeed(request)
    }

// Auth Middleware
object AuthMiddleware:
  def handle(authService: AuthService): Middleware = request =>
    request.headers.get("Authorization") match
      case Some(header) if header.startsWith("Bearer ") =>
        val token = header.stripPrefix("Bearer ")
        authService.validateToken(token).map { context =>
          request.copy(authResult = AuthResult.Authenticated(context))
        }
      case Some(header) if header.startsWith("ApiKey ") =>
        val key = header.stripPrefix("ApiKey ")
        authService.validateApiKey(key).map { context =>
          request.copy(authResult = AuthResult.ApiKeyAuth(context))
        }
      case _ =>
        ZIO.succeed(request.copy(authResult = AuthResult.Anonymous))
```

---

## 7. Circuit Breaker

```scala
package tracker.gateway.circuit

import zio._
import java.time.Instant

/** Состояние Circuit Breaker */
enum CircuitState:
  case Closed                            // Нормальная работа
  case Open(openedAt: Instant)           // Открыт, запросы отклоняются
  case HalfOpen(allowedRequests: Int)    // Пробные запросы

trait CircuitBreaker:
  def execute[A](serviceName: String)(call: Task[A]): Task[A]
  def getState(serviceName: String): UIO[CircuitState]

object CircuitBreaker:
  
  def make(config: CircuitBreakerConfig, redis: RedisClient): UIO[CircuitBreaker] =
    for
      states <- Ref.make(Map.empty[String, CircuitState])
    yield new CircuitBreaker:
      
      def execute[A](serviceName: String)(call: Task[A]): Task[A] =
        getState(serviceName).flatMap {
          case CircuitState.Closed =>
            call.tapError(_ => recordFailure(serviceName))
                .tap(_ => recordSuccess(serviceName))
                
          case CircuitState.Open(openedAt) =>
            val elapsed = Duration.between(openedAt, Instant.now())
            if elapsed > config.resetTimeout then
              transitionToHalfOpen(serviceName) *>
              execute(serviceName)(call)
            else
              ZIO.fail(new Exception(s"Circuit open for $serviceName"))
              
          case CircuitState.HalfOpen(allowed) if allowed > 0 =>
            call.tapError(_ => transitionToOpen(serviceName))
                .tap(_ => 
                  if allowed == 1 then transitionToClosed(serviceName)
                  else decrementHalfOpen(serviceName)
                )
                
          case CircuitState.HalfOpen(_) =>
            ZIO.fail(new Exception(s"Circuit half-open, no requests allowed"))
        }
      
      def recordFailure(serviceName: String): UIO[Unit] =
        // Инкремент счётчика ошибок, проверка порога
        ???
        
      def transitionToOpen(serviceName: String): UIO[Unit] =
        states.update(_.updated(serviceName, CircuitState.Open(Instant.now())))
```

---

## 8. Метрики и мониторинг

```yaml
# Prometheus метрики

# Счётчики запросов
gateway_requests_total{method, path, status, service}
gateway_rate_limited_total{key_type}
gateway_auth_failures_total{reason}
gateway_circuit_opens_total{service}

# Гистограммы
gateway_request_duration_seconds{method, path, service}
gateway_backend_duration_seconds{service}

# Gauge
gateway_active_connections
gateway_circuit_state{service}  # 0=closed, 1=half_open, 2=open
gateway_healthy_backends

# Примеры запросов PromQL
# RPS по сервисам
rate(gateway_requests_total[5m])

# P99 latency
histogram_quantile(0.99, rate(gateway_request_duration_seconds_bucket[5m]))

# Error rate
sum(rate(gateway_requests_total{status=~"5.."}[5m])) / sum(rate(gateway_requests_total[5m]))

# Алерты
- alert: HighErrorRate
  expr: sum(rate(gateway_requests_total{status=~"5.."}[5m])) / sum(rate(gateway_requests_total[5m])) > 0.05
  for: 5m
  annotations:
    summary: "API Gateway error rate > 5%"

- alert: CircuitBreakerOpen
  expr: gateway_circuit_state > 0
  for: 1m
  annotations:
    summary: "Circuit breaker open for {{ $labels.service }}"
```

---

## 9. Примеры запросов

### Аутентификация

```bash
# Login
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secret123"
  }'

# Response
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIs...",
  "expiresIn": 86400
}

# Refresh token
curl -X POST http://localhost:8080/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refreshToken": "eyJhbGciOiJIUzI1NiIs..."
  }'
```

### Защищённый endpoint

```bash
# Get devices
curl http://localhost:8080/api/v1/devices \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."

# Response Headers
X-Request-ID: 550e8400-e29b-41d4-a716-446655440000
X-Response-Time: 45
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1705750800
```

### Dashboard агрегация

```bash
curl http://localhost:8080/api/v1/dashboard \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."

# Response
{
  "vehiclesSummary": {
    "total": 150,
    "online": 120,
    "moving": 45,
    "stopped": 75,
    "offline": 30
  },
  "recentGeoEvents": [
    {
      "vehicleId": "uuid",
      "vehicleName": "А123BC",
      "eventType": "entered",
      "geozoneName": "Офис",
      "timestamp": "2025-01-20T10:30:00Z"
    }
  ],
  "analyticsSnapshot": {
    "totalDistanceToday": 12500,
    "totalTrips": 89,
    "averageSpeed": 35.5,
    "fuelUsed": 450.2
  },
  "maintenanceOverview": {
    "overdueCount": 3,
    "upcomingCount": 12,
    "completedThisMonth": 8
  },
  "timestamp": "2025-01-20T10:35:00Z"
}
```

---

## 10. AI Промпт для реализации сервиса

### Контекст и задача

```markdown
# Задача: Реализовать API Gateway для GPS трекинг системы

## Контекст
Единая точка входа для всех REST API запросов TrackerGPS системы.
Часть Блока 3 (Презентация). Маршрутизация, аутентификация JWT, rate limiting, Circuit Breaker.

## Технический стек (ОБЯЗАТЕЛЬНО)
- Scala 3.4.0
- ZIO 2.0.20 (эффекты, стримы, конкурентность)
- zio-http (HTTP сервер и клиент)
- zio-redis (rate limiting, кэш, сессии)
- zio-json (сериализация)
- zio-config (конфигурация из YAML)
- zio-logging (структурированное логирование)
- JWT (java-jwt или zio-jwt)

## Архитектурные компоненты

### 1. Слой домена (domain/)
```scala
// models.scala - Все case classes из раздела 2.1
// Включая: ServiceConfig, RouteRule, RateLimitConfig, UserContext,
// GatewayRequest, GatewayResponse, GatewayError

// config.scala
final case class GatewayConfig(
  port: Int,
  services: List[ServiceConfig],
  routes: List[RouteRule],
  global: GlobalConfig
)
```

### 2. Middleware (middleware/)
```scala
// Middleware.scala - Тип и композиция
type Middleware = GatewayRequest => ZIO[Any, GatewayError, GatewayRequest]

// CorsMiddleware.scala - CORS обработка
// RequestIdMiddleware.scala - Генерация X-Request-ID
// LoggingMiddleware.scala - Логирование запросов
// RateLimitMiddleware.scala - Rate limiting через Redis
// AuthMiddleware.scala - JWT валидация и API Key
// ValidationMiddleware.scala - Валидация запросов
```

### 3. Сервисы (service/)
```scala
// AuthService.scala - JWT валидация
trait AuthService:
  def validateToken(token: String): IO[GatewayError, UserContext]
  def validateApiKey(key: String): IO[GatewayError, ApiKeyContext]
  def invalidateToken(jti: String): UIO[Unit]

// RateLimiter.scala - Rate limiting
trait RateLimiter:
  def check(request: GatewayRequest, config: RateLimitConfig): UIO[RateLimitResult]
  def recordRequest(key: String): UIO[Unit]

// Router.scala - Маршрутизация к backend
trait Router:
  def route(request: GatewayRequest): IO[GatewayError, RouteRule]
  def forward(request: GatewayRequest, rule: RouteRule): IO[GatewayError, BackendResponse]

// ResponseAggregator.scala - Агрегация ответов
trait ResponseAggregator:
  def aggregate(request: GatewayRequest, endpoints: List[AggregationEndpoint]): IO[GatewayError, GatewayResponse]

// CircuitBreaker.scala - Circuit Breaker для backend
trait CircuitBreaker:
  def execute[A](serviceName: String)(call: Task[A]): Task[A]
  def getState(serviceName: String): UIO[CircuitState]
```

### 4. HTTP слой (http/)
```scala
// HttpClient.scala - Клиент для backend сервисов
trait HttpClient:
  def request(url: String, method: HttpMethod, headers: Map[String, String], body: Option[Array[Byte]]): Task[BackendResponse]

// GatewayRoutes.scala - HTTP endpoints
// - Системные: /health, /ready, /metrics
// - Проксирование: все остальные через Router
```

### 5. Кэширование (cache/)
```scala
// ResponseCache.scala
trait ResponseCache:
  def get(key: String): UIO[Option[CachedResponse]]
  def set(key: String, response: GatewayResponse, ttl: Duration): UIO[Unit]
  def invalidate(pattern: String): UIO[Unit]

// SessionCache.scala
trait SessionCache:
  def getSession(sessionId: UUID): UIO[Option[UserContext]]
  def setSession(sessionId: UUID, context: UserContext, ttl: Duration): UIO[Unit]
  def invalidateSession(sessionId: UUID): UIO[Unit]
```

### 6. Health (health/)
```scala
// HealthChecker.scala - Проверка backend сервисов
trait HealthChecker:
  def checkAll: UIO[GatewayHealth]
  def checkService(name: String): UIO[ServiceHealth]
  
// Фоновая задача проверки health каждые 10 секунд
```

## Требования к реализации

### Функциональные требования
1. JWT аутентификация с кэшированием сессий в Redis
2. API Key аутентификация для внешних интеграций
3. Rate limiting по IP/User/ApiKey с sliding window
4. Динамическая маршрутизация по конфигурации
5. Circuit Breaker для каждого backend сервиса
6. Агрегация ответов для dashboard
7. Response кэширование для GET запросов
8. CORS поддержка с настройкой origins

### Нефункциональные требования
1. Задержка добавленная gateway < 10ms
2. Обработка 10,000 RPS на инстанс
3. Graceful degradation при недоступности backend
4. Structured logging с request ID
5. Prometheus метрики для всех операций

### Критерии приёмки
1. Запрос без токена к защищённому endpoint возвращает 401
2. Запрос с истёкшим токеном возвращает 401
3. Превышение rate limit возвращает 429 с Retry-After
4. Circuit breaker открывается после N ошибок
5. Dashboard агрегация возвращает данные от всех сервисов
6. Health endpoint показывает статус всех backend
7. Метрики экспортируются в Prometheus формате

## Структура проекта
```
services/api-gateway/
├── src/main/scala/tracker/gateway/
│   ├── Main.scala
│   ├── GatewayApp.scala
│   ├── domain/
│   │   ├── models.scala
│   │   ├── config.scala
│   │   └── errors.scala
│   ├── middleware/
│   │   ├── Middleware.scala
│   │   ├── CorsMiddleware.scala
│   │   ├── RequestIdMiddleware.scala
│   │   ├── LoggingMiddleware.scala
│   │   ├── RateLimitMiddleware.scala
│   │   ├── AuthMiddleware.scala
│   │   └── ValidationMiddleware.scala
│   ├── service/
│   │   ├── AuthService.scala
│   │   ├── RateLimiter.scala
│   │   ├── Router.scala
│   │   ├── ResponseAggregator.scala
│   │   └── CircuitBreaker.scala
│   ├── http/
│   │   ├── HttpClient.scala
│   │   └── GatewayRoutes.scala
│   ├── cache/
│   │   ├── ResponseCache.scala
│   │   └── SessionCache.scala
│   └── health/
│       └── HealthChecker.scala
├── src/main/resources/
│   ├── application.conf
│   └── routes.yaml
└── src/test/scala/tracker/gateway/
    ├── middleware/
    │   └── RateLimitMiddlewareSpec.scala
    └── service/
        └── CircuitBreakerSpec.scala
```

## Примеры вызовов
Использовать примеры из раздела 9 документации.
```

---

## Связанные документы

- [ARCHITECTURE_BLOCK3.md](../ARCHITECTURE_BLOCK3.md) - Обзор блока презентации
- [AUTH_SERVICE.md](./AUTH_SERVICE.md) - Сервис аутентификации
- [WEBSOCKET_SERVICE.md](./WEBSOCKET_SERVICE.md) - WebSocket для real-time
