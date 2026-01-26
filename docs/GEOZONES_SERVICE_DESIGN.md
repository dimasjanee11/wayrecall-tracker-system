# 🗺️ Geozones Service — Дизайн и оптимизации

> **Дата:** 25 января 2026  
> **Статус:** Проектирование

---

## 📋 Ответственность сервиса

**Geozones Service** — единственный сервис, который:
1. Хранит и управляет геозонами
2. Проверяет точки на вхождение в геозоны
3. Оптимизирует проверки (кеш, батчинг, пространственные индексы)
4. Генерирует события enter/leave в Kafka
5. Хранит текущее состояние "машина → геозоны"

**Никто другой НЕ лезет в PostGIS с геозонами напрямую!**

---

## 🏗️ Архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GEOZONES SERVICE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐       │
│  │  Kafka Consumer │     │   gRPC Server   │     │  REST API       │       │
│  │  (gps-events)   │     │  (внутренние)   │     │  (CRUD геозон)  │       │
│  └────────┬────────┘     └────────┬────────┘     └────────┬────────┘       │
│           │                       │                       │                 │
│           ▼                       ▼                       ▼                 │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                    OPTIMIZATION LAYER                            │      │
│  │                                                                  │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │      │
│  │  │ Spatial Grid │  │ Point Buffer │  │ Result Cache │           │      │
│  │  │    Index     │  │   (Batch)    │  │   (Redis)    │           │      │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │      │
│  │                                                                  │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │      │
│  │  │ Geohash      │  │ Coord Round  │  │ State Diff   │           │      │
│  │  │ Pre-filter   │  │  (30 meters) │  │  (enter/lv)  │           │      │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                      DATA LAYER                                  │      │
│  │                                                                  │      │
│  │  ┌──────────────────┐          ┌──────────────────┐             │      │
│  │  │    PostgreSQL    │          │      Redis       │             │      │
│  │  │  + PostGIS       │          │                  │             │      │
│  │  │                  │          │  • Result cache  │             │      │
│  │  │  • geozones      │          │  • Vehicle state │             │      │
│  │  │  • spatial_grid  │          │  • Grid index    │             │      │
│  │  │  • GiST indexes  │          │  • Rate limits   │             │      │
│  │  └──────────────────┘          └──────────────────┘             │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────┐                                                      │
│  │  Kafka Producer  │  → geozone-events (enter/leave)                      │
│  └──────────────────┘                                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Крутые оптимизации

### 1. 🔲 Spatial Grid Index (Пространственная сетка)

**Идея:** Разбить мир на квадраты (например, 1км × 1км) и заранее знать какие геозоны в каком квадрате.

```sql
-- Таблица сетки
CREATE TABLE spatial_grid (
    cell_id VARCHAR(20) PRIMARY KEY,  -- "u8vxn" (geohash)
    geozones_ids INTEGER[]             -- {5, 12, 45, 78}
);

-- При добавлении геозоны автоматически заполняем сетку
CREATE OR REPLACE FUNCTION update_grid_on_geozone_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Находим все ячейки, которые пересекает геозона
    INSERT INTO spatial_grid (cell_id, geozones_ids)
    SELECT 
        ST_GeoHash(cell.geom, 5) as cell_id,
        array_agg(NEW.id)
    FROM (
        SELECT (ST_SquareGrid(0.01, NEW.geometry)).*  -- ~1км сетка
    ) cell
    WHERE ST_Intersects(cell.geom, NEW.geometry)
    ON CONFLICT (cell_id) 
    DO UPDATE SET geozones_ids = spatial_grid.geozones_ids || NEW.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Использование:**
```scala
// Шаг 1: Получить geohash точки (быстро, без БД)
val cellId = GeoHash.encode(lat, lon, precision = 5)  // "u8vxn"

// Шаг 2: Проверить Redis кеш сетки
val nearbyGeozones = redis.get(s"grid:$cellId")  // [5, 12, 45]

// Шаг 3: Если пусто — нет геозон в радиусе 1км, SKIP!
if (nearbyGeozones.isEmpty) return Set.empty

// Шаг 4: Проверить только nearby геозоны в PostGIS
val result = postgis.query(
  "SELECT id FROM geozones WHERE id = ANY(?) AND ST_Covers(geometry, ?)",
  nearbyGeozones, point
)
```

**Профит:**
- 90% точек в "пустых" ячейках → 0 запросов к PostGIS
- Вместо проверки 10K геозон проверяем 3-5

---

### 2. 📦 Batch Processing (Батчинг)

**Идея:** Накапливать точки и проверять пачками.

```scala
class GeozoneCheckBatcher(
    batchSize: Int = 100,
    maxWait: Duration = 500.millis
) {
  private val buffer = new ConcurrentLinkedQueue[CheckRequest]()
  
  def check(vehicleId: String, lon: Double, lat: Double): ZIO[Any, Nothing, Set[GeozoneId]] = {
    for {
      promise <- Promise.make[Nothing, Set[GeozoneId]]
      _       <- ZIO.succeed(buffer.add(CheckRequest(vehicleId, lon, lat, promise)))
      result  <- promise.await
    } yield result
  }
  
  // Фоновый процесс обработки батчей
  val batchProcessor: ZIO[Any, Nothing, Unit] = {
    for {
      batch  <- collectBatch(batchSize, maxWait)
      _      <- processBatch(batch).fork  // Не блокируем следующий батч
    } yield ()
  }.forever
  
  private def processBatch(batch: List[CheckRequest]): Task[Unit] = {
    // ОДИН запрос для всех точек!
    val sql = """
      WITH points AS (
        SELECT unnest(?::varchar[]) as vehicle_id,
               unnest(?::float[]) as lon,
               unnest(?::float[]) as lat
      )
      SELECT p.vehicle_id, array_agg(g.id) as geozone_ids
      FROM points p
      LEFT JOIN geozones g ON ST_Covers(g.geometry, ST_MakePoint(p.lon, p.lat))
      GROUP BY p.vehicle_id
    """
    // ...
  }
}
```

**Профит:**
- Вместо 100 запросов — 1 запрос
- PostgreSQL оптимизирует один большой запрос лучше чем 100 маленьких

---

### 3. 🎯 Geohash Pre-filter (Быстрый отсев)

**Идея:** Хранить bounding box геозон как geohash-ы для мгновенной фильтрации.

```scala
case class GeozoneCache(
    id: Int,
    geohashPrefix: String,     // "u8vxn" — центр геозоны
    boundingRadius: Double,    // Радиус описанной окружности в метрах
    minLon: Double, maxLon: Double,
    minLat: Double, maxLat: Double
)

def quickFilter(point: Point, geozones: List[GeozoneCache]): List[GeozoneCache] = {
  geozones.filter { gz =>
    // Быстрая проверка bounding box (без БД!)
    point.lon >= gz.minLon && point.lon <= gz.maxLon &&
    point.lat >= gz.minLat && point.lat <= gz.maxLat
  }
}
```

**Профит:**
- Фильтрация в памяти за O(n) без обращения к БД
- Типично отсекает 99% геозон

---

### 4. 🔄 Coordinate Rounding + Cache (как в Stels, но лучше)

```scala
object CoordRounder {
  // 0.0003 градуса ≈ 30 метров
  // 0.0001 градуса ≈ 10 метров  
  val precision = 0.0003
  
  def round(coord: Double): Double = 
    math.round(coord / precision) * precision
    
  def cacheKey(vehicleId: String, lon: Double, lat: Double): String =
    s"geocheck:$vehicleId:${round(lon)}:${round(lat)}"
}

// Redis кеш с TTL
def checkWithCache(vehicleId: String, lon: Double, lat: Double): Task[Set[GeozoneId]] = {
  val key = CoordRounder.cacheKey(vehicleId, lon, lat)
  
  redis.get(key).flatMap {
    case Some(cached) => ZIO.succeed(cached.parseGeozoneIds)
    case None => 
      for {
        result <- postgisCheck(vehicleId, lon, lat)
        _      <- redis.setex(key, 30.seconds, result.toJson)
      } yield result
  }
}
```

---

### 5. 📊 Adaptive Check Frequency (Адаптивная частота)

**Идея:** Умная частота проверки в зависимости от ситуации.

```scala
case class CheckPolicy(
    vehicleId: String,
    lastCheck: Instant,
    lastGeozones: Set[GeozoneId],
    speed: Double,
    nearestGeozoneDistance: Option[Double]
)

def shouldCheck(policy: CheckPolicy, now: Instant): Boolean = {
  val timeSinceLastCheck = Duration.between(policy.lastCheck, now)
  
  policy match {
    // Стоит на месте → проверяем редко
    case p if p.speed < 1.0 => 
      timeSinceLastCheck > 5.minutes
      
    // Далеко от геозон → проверяем редко  
    case p if p.nearestGeozoneDistance.exists(_ > 1000) => 
      timeSinceLastCheck > 30.seconds
      
    // Близко к границе геозоны → проверяем часто!
    case p if p.nearestGeozoneDistance.exists(_ < 100) =>
      timeSinceLastCheck > 2.seconds
      
    // Обычный режим
    case _ => 
      timeSinceLastCheck > 10.seconds
  }
}
```

**Профит:**
- Стоящие машины не грузят систему
- Машины далеко от геозон не грузят систему
- Машины у границы геозоны проверяются часто (точность)

---

### 6. 🌐 R-tree in Redis (Пространственный индекс в памяти)

**Идея:** Держать легковесный R-tree индекс геозон в Redis для мгновенного поиска.

```lua
-- Redis Lua скрипт для проверки точки
-- Используем GEOSEARCH (Redis 6.2+)

-- Шаг 1: Найти геозоны в радиусе
local nearby = redis.call('GEOSEARCH', 'geozones:centers', 
    'FROMLONLAT', lon, lat, 
    'BYRADIUS', 5, 'km',
    'ASC', 'COUNT', 20)

-- Шаг 2: Для найденных проверить точное вхождение
local result = {}
for _, gz_id in ipairs(nearby) do
    local polygon = redis.call('GET', 'geozone:' .. gz_id .. ':wkt')
    -- Здесь нужна проверка point-in-polygon в Lua или вернуть в приложение
end
return result
```

```scala
// Scala обёртка
def redisGeoCheck(lon: Double, lat: Double): Task[List[GeozoneId]] = {
  for {
    // Шаг 1: Быстрый поиск по центрам (Redis)
    nearby <- redis.geoSearch("geozones:centers", lon, lat, radius = 5.km)
    
    // Шаг 2: Если пусто — точно нет геозон
    if nearby.isEmpty => ZIO.succeed(Nil)
    
    // Шаг 3: Точная проверка в PostGIS только для nearby
    result <- postgis.query(
      "SELECT id FROM geozones WHERE id = ANY(?) AND ST_Covers(geometry, ?)",
      nearby.map(_.id), point
    )
  } yield result
}
```

---

### 7. 🔔 Smart State Diff (Умное определение enter/leave)

```scala
case class VehicleGeozoneState(
    vehicleId: String,
    currentGeozones: Set[GeozoneId],
    lastUpdate: Instant,
    pendingEnter: Map[GeozoneId, Instant],  // Ожидание подтверждения входа
    pendingLeave: Map[GeozoneId, Instant]   // Ожидание подтверждения выхода
)

def updateState(
    state: VehicleGeozoneState,
    newGeozones: Set[GeozoneId],
    now: Instant
): (VehicleGeozoneState, List[GeozoneEvent]) = {
  
  val rawEntered = newGeozones -- state.currentGeozones
  val rawLeft = state.currentGeozones -- newGeozones
  
  // Защита от "дребезга" на границе геозоны
  val confirmedEnter = state.pendingEnter.filter { case (id, since) =>
    rawEntered.contains(id) && Duration.between(since, now) > 5.seconds
  }.keySet
  
  val confirmedLeave = state.pendingLeave.filter { case (id, since) =>
    rawLeft.contains(id) && Duration.between(since, now) > 5.seconds
  }.keySet
  
  val events = 
    confirmedEnter.map(id => GeozoneEnterEvent(state.vehicleId, id, now)).toList ++
    confirmedLeave.map(id => GeozoneLeaveEvent(state.vehicleId, id, now)).toList
    
  val newState = state.copy(
    currentGeozones = (state.currentGeozones ++ confirmedEnter) -- confirmedLeave,
    pendingEnter = state.pendingEnter ++ rawEntered.map(_ -> now) -- confirmedEnter,
    pendingLeave = state.pendingLeave ++ rawLeft.map(_ -> now) -- confirmedLeave,
    lastUpdate = now
  )
  
  (newState, events)
}
```

**Профит:**
- Нет ложных срабатываний при "дребезге" GPS на границе
- Подтверждение через 5 секунд повторного нахождения в/вне зоны

---

### 8. 📈 Metrics & Observability

```scala
object GeozoneMetrics {
  val checksTotal = Counter("geozone_checks_total", "vehicle_id")
  val cacheHits = Counter("geozone_cache_hits_total")
  val cacheMisses = Counter("geozone_cache_misses_total")
  val gridSkips = Counter("geozone_grid_skips_total")  // Точка в пустой ячейке
  val postgisQueries = Counter("geozone_postgis_queries_total")
  val postgisLatency = Histogram("geozone_postgis_latency_seconds")
  val enterEvents = Counter("geozone_enter_events_total", "geozone_id")
  val leaveEvents = Counter("geozone_leave_events_total", "geozone_id")
}
```

---

## 📊 Итоговая оптимизация

```
Входящие точки:                   10,000 точек/сек

После Adaptive Frequency:         ~2,000 точек/сек
(80% машин стоят или далеко)      ↓ 5x

После Spatial Grid Skip:          ~400 точек/сек
(80% точек в пустых ячейках)      ↓ 5x

После Coord Round Cache:          ~80 точек/сек
(80% cache hit)                   ↓ 5x

После Batching:                   ~8 PostGIS запросов/сек
(100 точек в батче)               ↓ 10x

═══════════════════════════════════════════════
ИТОГО: 10,000 → 8 запросов к PostGIS в секунду
═══════════════════════════════════════════════
```

---

## 🗃️ Схема данных

### PostgreSQL (PostGIS)

```sql
-- Основная таблица геозон
CREATE TABLE geozones (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    geometry GEOGRAPHY(POLYGON, 4326) NOT NULL,
    color VARCHAR(7) DEFAULT '#FF0000',
    
    -- Кеширование для быстрой фильтрации
    center_lon DOUBLE PRECISION GENERATED ALWAYS AS (ST_X(ST_Centroid(geometry::geometry))) STORED,
    center_lat DOUBLE PRECISION GENERATED ALWAYS AS (ST_Y(ST_Centroid(geometry::geometry))) STORED,
    bounding_radius_m DOUBLE PRECISION,  -- Радиус описанной окружности
    geohash_prefix VARCHAR(12),          -- Для spatial grid
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- GiST индекс для ST_Covers
CREATE INDEX idx_geozones_geometry ON geozones USING GIST (geometry);

-- Индекс для фильтрации по организации
CREATE INDEX idx_geozones_org ON geozones (organization_id);

-- Пространственная сетка (автозаполняется триггером)
CREATE TABLE spatial_grid (
    cell_geohash VARCHAR(12) PRIMARY KEY,
    geozone_ids INTEGER[] NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Redis

```redis
# Кеш результатов проверки (TTL 30 сек)
SET geocheck:{vehicle_id}:{rounded_lon}:{rounded_lat} "[5,12,45]" EX 30

# Текущее состояние машины (TTL 24 часа)
HSET vehicle:state:{vehicle_id} 
    geozones "[5,12,45]"
    last_check "2026-01-25T14:30:00Z"
    pending_enter "{12: '2026-01-25T14:29:55Z'}"
    pending_leave "{}"

# Центры геозон для GEOSEARCH
GEOADD geozones:centers 37.6175 55.7558 "geozone:5"
GEOADD geozones:centers 37.5883 55.7330 "geozone:12"

# Spatial Grid кеш
SET grid:u8vxn "[5,12,45]" EX 3600
SET grid:u8vxp "[]" EX 3600  # Пустая ячейка тоже кешируется!

# Метаданные геозон (для быстрого доступа без PostGIS)
HSET geozone:5
    name "Склад №1"
    org_id "42"
    center_lon "37.6175"
    center_lat "55.7558"
    radius_m "500"
```

---

## 🎯 API сервиса

### gRPC (для внутренних сервисов)

```protobuf
service GeozonesService {
    // Проверить точку (с оптимизациями)
    rpc CheckPoint(CheckPointRequest) returns (CheckPointResponse);
    
    // Batch проверка (для History Writer)
    rpc CheckPointsBatch(CheckPointsBatchRequest) returns (CheckPointsBatchResponse);
    
    // Стриминг проверок (для Kafka consumer)
    rpc CheckPointsStream(stream GpsPoint) returns (stream GeozoneEvent);
    
    // Получить текущее состояние машины
    rpc GetVehicleState(VehicleId) returns (VehicleGeozoneState);
}
```

### REST API (для UI)

```yaml
paths:
  /geozones:
    get:
      summary: Список геозон организации
    post:
      summary: Создать геозону
      
  /geozones/{id}:
    get:
      summary: Получить геозону
    put:
      summary: Обновить геозону
    delete:
      summary: Удалить геозону
      
  /geozones/check:
    post:
      summary: Проверить точку (для отладки)
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                lon: number
                lat: number
                vehicle_id: string
```

---

## ✅ Резюме

**Geozones Service** — это "умный" сервис который:

1. **Принимает** GPS точки из Kafka
2. **Фильтрует** через Spatial Grid (90% отсев)
3. **Кеширует** через Coord Rounding (90% cache hit)
4. **Батчит** запросы к PostGIS
5. **Определяет** enter/leave с защитой от дребезга
6. **Публикует** события в Kafka

**Результат:** из 10,000 точек/сек делаем ~8 запросов к PostGIS!

---

**Следующие шаги:**
- [ ] Создать структуру модуля geozones-service
- [ ] Реализовать Spatial Grid
- [ ] Реализовать Adaptive Check Frequency
- [ ] Написать тесты производительности

---

**Дата:** 25 января 2026  
**Статус:** Дизайн завершён ✅
