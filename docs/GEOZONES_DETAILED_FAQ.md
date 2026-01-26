# 📋 Детальные ответы на вопросы по архитектуре

> **Дата:** 25 января 2026

---

## 1️⃣ В старом Stels в геозоны приходили все точки или отфильтрованные?

### Ответ: ВСЕ точки, но с буферизацией

```
PackReceiver (TCP/UDP)
       │
       ▼ JMS (ActiveMQ)
       │
       ▼ GPSEvent publish
       │
       ▼ GpsNotificationDetector.onGpsEvent()
       │
       ▼ GPSDataWindow (буфер 6 сек!)  ← Вот здесь фильтрация
       │
       ▼ processGps() → проверка геозон + скорости + датчиков
```

**Ключевой код из Stels:**

```scala
// GpsNotificationDetector.scala, строка 94-99
def onGpsEvent(gps: GPSEvent): Unit = {
  if (gps.gpsData.unchained())  // Пропускаем "открепленные" точки
    return;
  cachedWindowses.get(gps.gpsData.uid).enqueue(gps.gpsData)  // В буфер!
}
```

**GPSDataWindow** — накапливает точки и отдаёт последнюю за 6 секунд:
- `windowMills = 6000` (6 секунд)
- Если машина шлёт 1 точку/сек → обрабатывается ~17% точек

**Вывод:** Точки НЕ фильтровались "по правилам" на входе. Фильтрация была **по времени** (буфер).

---

## 2️⃣ Как работали геозоны и скорости в старом Stels

### Архитектура была МОНОЛИТНАЯ — всё в одном классе!

```scala
// GpsNotificationDetector.scala, строка 156-172
protected[this] def processGps(gps: GPSData) {
  val uid = gpsData.uid
  
  // 1. Загрузить ВСЕ правила для этого объекта
  val rules = cachedRules(uid)  // Guava Cache, 300 сек TTL
  
  // 2. Разделить на типы
  val (geozonesRules, otherRules) = rules.partition(_.isInstanceOf[GeozoneNotificationRule])
  
  // 3. Проверить геозоны
  val geozoneNotifications = geozones.detectToNotifyGeozones(geozonesRules, gpsData, uid)
  
  // 4. Проверить остальное (скорость, датчики, пробег и т.д.)
  val otherNotifications = detectToNotify(otherRules, gpsData, uid)
  
  // 5. Отправить уведомления
  for (n <- geozoneNotifications ++ otherNotifications) {
    notifyUser(n, "Событие")
  }
}
```

### Проверка скорости (SpeedNotificationRule):

```scala
// SpeedNotificationRule.scala
class SpeedNotificationRule(base: NotificationRule[GPSData], val maxValue: Double) {
  
  override def process(gps: GPSData, state: Map[String, AnyRef]) = {
    new GpsNotificationStateChange(notificationId, gps, state) {
      
      // Просто сравниваем скорость с лимитом!
      def fired = gps.speed > maxValue
      
      def notifications = Seq(Notification(...))
    }
  }
}
```

### Проверка геозон:

```scala
// GpsNotificationDetector.scala, строка 316-350
def detectToNotifyGeozones(geo: List[GeozoneNotificationRule], gpsData: GPSData, uid: String) = {
  if (geo.isEmpty || !gpsData.containsLonLat())
    return List.empty

  // 1. Только ID геозон из правил
  val geoIds = geo.map(_.geozoneId).toArray
  
  // 2. Округление + кеш
  val geozonesWithPoint = geozonesCache(geoIds, round(gpsData.lon), round(gpsData.lat))
  
  // 3. Текущие геозоны
  val curGeozones = geozonesWithPoint.map(_.id).toSet
  
  // 4. Предыдущее состояние из MongoDB
  val prevGeozones = mdbm.getDatabase()("geoZonesState")
    .findOne(MongoDBObject("uid" -> uid))
    .map(_.as[MongoDBList]("geozones").toSet)
    .getOrElse(Set.empty)
  
  // 5. Вычислить enter/leave
  val enteredGeozones = curGeozones -- prevGeozones
  val leftGeozones = prevGeozones -- curGeozones
  
  // 6. Обновить состояние
  mdbm.getDatabase()("geoZonesState").update(...)
  
  // 7. Найти правила которые сработали
  val toNotify = geo.filter(rule => 
    (rule.onLeave && leftGeozones(rule.geozoneId)) || 
    (!rule.onLeave && enteredGeozones(rule.geozoneId))
  )
  
  return toNotify.flatMap(_.process(gpsData, null).notifications)
}
```

### Схема потока данных в Stels:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         STELS МОНОЛИТ                                     │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  GPSEvent (JMS)                                                          │
│       │                                                                   │
│       ▼                                                                   │
│  ┌─────────────────────────────────────────────────────────────────┐     │
│  │  GpsNotificationDetector.onGpsEvent()                           │     │
│  │                                                                  │     │
│  │  GPSDataWindow (буфер 6 сек, Guava Cache)                       │     │
│  │       │                                                          │     │
│  │       ▼                                                          │     │
│  │  processGps(gpsData)                                            │     │
│  │       │                                                          │     │
│  │       ├─── cachedRules(uid)  ← MongoDB + Guava Cache 300 сек    │     │
│  │       │                                                          │     │
│  │       ├─► GeozoneNotificationRule[]                             │     │
│  │       │        │                                                 │     │
│  │       │        ▼                                                 │     │
│  │       │   detectToNotifyGeozones()                              │     │
│  │       │        │                                                 │     │
│  │       │        ├── geozonesCache (Guava, 20 сек, round coords)  │     │
│  │       │        │        │                                        │     │
│  │       │        │        ▼ Cache MISS                            │     │
│  │       │        │   GeozonesStore.getUsersGeozonesWithPoint()    │     │
│  │       │        │        │                                        │     │
│  │       │        │        ▼                                        │     │
│  │       │        │   PostgreSQL + PostGIS (ST_Covers)             │     │
│  │       │        │                                                 │     │
│  │       │        ├── geoZonesState (MongoDB) ← prev state         │     │
│  │       │        │                                                 │     │
│  │       │        └── enter/leave events                           │     │
│  │       │                                                          │     │
│  │       ├─► SpeedNotificationRule[]                               │     │
│  │       │        │                                                 │     │
│  │       │        └── if (gps.speed > maxValue) → fired            │     │
│  │       │                                                          │     │
│  │       ├─► ParamNotificationRule[] (датчики)                     │     │
│  │       │        │                                                 │     │
│  │       │        └── if (param < min || param > max) → fired      │     │
│  │       │                                                          │     │
│  │       └─► notifyUser() → Email, SMS, Push                       │     │
│  │                                                                  │     │
│  └─────────────────────────────────────────────────────────────────┘     │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 3️⃣ Подробные пояснения: как будет работать, где хранится, какие ресурсы

### Вариант A: Без Rules Engine (как в Stels, но микросервисы)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  Connection Manager                                                     │
│       │                                                                 │
│       ▼                                                                 │
│  Kafka: gps-events (ВСЕ точки)                                         │
│       │                                                                 │
│       ├────────────────────────────────────────────────────┐           │
│       │                                                     │           │
│       ▼                                                     ▼           │
│  ┌─────────────┐                                    ┌─────────────┐    │
│  │  Geozones   │  Kafka Consumer                    │  Speed      │    │
│  │  Service    │  Group: geozones-service           │  Service    │    │
│  │             │                                    │             │    │
│  │  • Загружает правила для vehicleId              │  • Загружает│    │
│  │  • Если нет правил с геозонами → SKIP           │    правила  │    │
│  │  • Проверяет геозоны                            │  • Проверяет│    │
│  │  • Публикует enter/leave                        │    скорость │    │
│  └─────────────┘                                    └─────────────┘    │
│                                                                         │
│  Проблема: КАЖДЫЙ сервис загружает правила для КАЖДОЙ точки!          │
│  = много дублирования, много запросов к БД правил                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Ресурсы для Варианта A:**
- Geozones Service: 2 vCPU, 2 GB RAM, PostGIS 1 GB
- Speed Service: 1 vCPU, 512 MB RAM
- Rules DB: PostgreSQL для хранения правил (дублируется в каждом сервисе)

### Вариант B: С Rules Engine (маршрутизатор)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  Connection Manager                                                     │
│       │                                                                 │
│       ▼                                                                 │
│  Kafka: gps-events (ВСЕ точки)                                         │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Rules Engine (ЕДИНСТВЕННЫЙ сервис с правилами)                 │   │
│  │                                                                  │   │
│  │  Redis Cache: rules:{vehicleId} → List[Rule]                    │   │
│  │                                                                  │   │
│  │  for (point <- kafkaStream) {                                   │   │
│  │    val rules = rulesCache.get(point.vehicleId)                  │   │
│  │                                                                  │   │
│  │    // Фильтруем по правилам!                                    │   │
│  │    if (rules.hasGeozoneRules) {                                 │   │
│  │      kafka.send("geozone-checks", GeozoneCheckRequest(          │   │
│  │        vehicleId, point, rules.geozoneIds                       │   │
│  │      ))                                                          │   │
│  │    }                                                             │   │
│  │                                                                  │   │
│  │    if (rules.hasSpeedRules) {                                   │   │
│  │      // Проверяем скорость прямо здесь (простая логика)         │   │
│  │      if (point.speed > rules.speedLimit) {                      │   │
│  │        kafka.send("alerts", SpeedAlert(...))                    │   │
│  │      }                                                           │   │
│  │    }                                                             │   │
│  │  }                                                               │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│       │                                                                 │
│       ▼                                                                 │
│  Kafka: geozone-checks (ТОЛЬКО точки с правилами на геозоны!)         │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Geozones Service (НЕ знает про правила!)                       │   │
│  │                                                                  │   │
│  │  Получает: { vehicleId, point, geozoneIds: [5, 12, 45] }        │   │
│  │  Возвращает: { insideGeozones: [5, 12] }                        │   │
│  │                                                                  │   │
│  │  Всё! Просто проверяет точку на конкретные геозоны.            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Ресурсы для Варианта B:**
- **Rules Engine**: 2 vCPU, 1 GB RAM (правила в Redis)
- **Geozones Service**: 1 vCPU, 512 MB RAM + PostGIS 1 GB (только геозоны, без правил!)
- **Speed Service**: НЕ НУЖЕН (логика в Rules Engine)
- **Redis**: 512 MB (правила + состояние)

---

## 4️⃣ Spatial Grid Index — сколько займёт, где хранится, кто сосед

### Размер сетки

**Параметры:**
- Precision 5 в Geohash = ячейка ~4.9km × 4.9km
- Precision 6 = ~1.2km × 0.6km
- Precision 7 = ~153m × 153m

**Для Москвы + область (~50,000 км²):**
```
Precision 5: ~2,000 ячеек × 100 байт = 200 KB
Precision 6: ~70,000 ячеек × 100 байт = 7 MB
Precision 7: ~2,000,000 ячеек × 100 байт = 200 MB  ← Слишком много!
```

**Рекомендация:** Precision 6 (~1км сетка) = **7 MB в Redis**

### Где хранится

```redis
# Вариант 1: Redis Hash
HSET grid:geozones u8vxnp "[5, 12, 45]"
HSET grid:geozones u8vxnq "[12, 78]"
HSET grid:geozones u8vxnr "[]"  # Пустая ячейка!

# TTL: 1 час (обновляется при изменении геозон)
EXPIRE grid:geozones 3600
```

```sql
-- Вариант 2: PostgreSQL (для persistence)
CREATE TABLE spatial_grid (
    cell_geohash VARCHAR(12) PRIMARY KEY,
    geozone_ids INTEGER[] NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ~70,000 строк для Москвы = 7 MB
```

### Как понять кто сосед квадрата

**Geohash имеет встроенную иерархию!**

```
Geohash "u8vxnp" имеет 8 соседей:
   u8vxnn | u8vxnq | u8vxnr
   -------+--------+-------
   u8vxnm | u8vxnp | u8vxns   ← центр
   -------+--------+-------
   u8vxnj | u8vxnk | u8vxnt
```

**Библиотека для Scala:**
```scala
// Используем geohash-java или ch.hsr.geohash
import ch.hsr.geohash.GeoHash

val center = GeoHash.withCharacterPrecision(55.7558, 37.6173, 6)  // "ucftpz"
val neighbors = center.getAdjacent  // Все 8 соседей

// Или вручную (алгоритм Geohash детерминированный)
def getNeighbors(hash: String): List[String] = {
  val gh = GeoHash.fromGeohashString(hash)
  List(
    gh.getNorthernNeighbour,
    gh.getSouthernNeighbour,
    gh.getEasternNeighbour,
    gh.getWesternNeighbour,
    // ... и диагонали
  ).map(_.toBase32)
}
```

---

## 5️⃣ При добавлении геозоны — как присваивается сетка?

### Да, именно так! При CRUD геозоны обновляем сетку

```scala
// Geozones Service — обработка создания/изменения геозоны
def onGeozoneCreated(geozone: Geozone): Task[Unit] = {
  for {
    // 1. Найти все ячейки, которые пересекает геозона
    cells <- postgis.query("""
      SELECT ST_GeoHash(cell.geom, 6) as cell_id
      FROM (
        SELECT (ST_SquareGrid(0.01, ?)).*
      ) cell
      WHERE ST_Intersects(cell.geom, ?)
    """, geozone.boundingBox, geozone.geometry)
    
    // 2. Обновить Redis для каждой ячейки
    _ <- ZIO.foreachDiscard(cells) { cellId =>
      redis.sAdd(s"grid:$cellId", geozone.id.toString)
    }
    
    // 3. Инвалидировать кеш для затронутых машин
    _ <- invalidateAffectedVehicles(cells)
    
  } yield ()
}

def onGeozoneDeleted(geozoneId: Int): Task[Unit] = {
  for {
    // 1. Найти все ячейки где была эта геозона
    cells <- redis.keys("grid:*").filter(cell => 
      redis.sIsMember(cell, geozoneId.toString)
    )
    
    // 2. Удалить из каждой ячейки
    _ <- ZIO.foreachDiscard(cells) { cellId =>
      redis.sRem(cellId, geozoneId.toString)
    }
  } yield ()
}
```

### Пример:

```
Геозона "Склад №1" (полигон 500м × 300м)
       │
       ▼ ST_Intersects с сеткой
       │
       ▼ Пересекает ячейки: [u8vxnp, u8vxnq, u8vxnm, u8vxnn]
       │
       ▼ Redis:
         SET grid:u8vxnp "[5]"
         SET grid:u8vxnq "[5]"
         SET grid:u8vxnm "[5]"
         SET grid:u8vxnn "[5]"
```

---

## 6️⃣ In-memory накапливание перед батчем — оптимально ли?

### Краткий ответ: НЕТ, не оптимально для микросервисов!

**Проблемы in-memory буфера:**
1. **Потеря данных** при падении сервиса
2. **Сложность** при горизонтальном масштабировании
3. **Неравномерная нагрузка** — один инстанс может накопить больше

### Лучшие альтернативы:

#### Вариант A: Kafka Streams с windowing

```scala
// Kafka Streams автоматически батчит!
val stream = builder.stream[String, GpsEvent]("gps-events")

stream
  .groupByKey()
  .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofSeconds(10)))
  .aggregate(
    () => List.empty[GpsEvent],
    (key, event, list) => list :+ event
  )
  .toStream()
  .foreach { case (windowedKey, batch) =>
    geozonesService.checkBatch(batch)  // Батч из Kafka!
  }
```

**Плюсы:**
- Kafka хранит данные (не потеряются)
- Автоматическое масштабирование
- Exactly-once семантика

#### Вариант B: Redis Streams как буфер

```scala
// Producer (Rules Engine)
redis.xAdd("geozone-checks", Map(
  "vehicleId" -> vehicleId,
  "lon" -> lon.toString,
  "lat" -> lat.toString,
  "geozoneIds" -> geozoneIds.mkString(",")
))

// Consumer (Geozones Service) — читаем батчами
val batch = redis.xRead(
  count = 100,
  block = 500.millis,
  streams = Map("geozone-checks" -> ">")
)
processBatch(batch)
```

#### Вариант C: PostgreSQL COPY для батчинга (как в History Writer)

```scala
// Накапливаем в Kafka, пишем батчами через COPY
kafkaStream
  .groupedWithin(1000, 1.second)
  .mapAsync(4) { batch =>
    postgis.copyIn("gps_check_buffer", batch)
  }

// Затем один SQL запрос для всего батча
postgis.query("""
  WITH checks AS (SELECT * FROM gps_check_buffer)
  SELECT c.vehicle_id, array_agg(g.id)
  FROM checks c
  LEFT JOIN geozones g ON ST_Covers(g.geometry, ST_MakePoint(c.lon, c.lat))
  GROUP BY c.vehicle_id
""")
```

### Рекомендация: **Kafka Streams windowing** — самый надёжный вариант

---

## 7️⃣ Rules Engine — нужен ли дополнительный сервис? Докажи!

### Аргументы ЗА Rules Engine:

#### 1. **Single Responsibility**

```
БЕЗ Rules Engine:
┌─────────────────────────────────────────────────────────────────┐
│ Geozones Service                                                │
│   • Знает про геозоны ✓                                        │
│   • Знает про правила уведомлений ✗ (не его ответственность!)  │
│   • Знает какие машины к какой организации ✗                   │
│   • Знает типы уведомлений (email/sms) ✗                       │
└─────────────────────────────────────────────────────────────────┘

С Rules Engine:
┌─────────────────────────────────────────────────────────────────┐
│ Geozones Service                                                │
│   • Знает про геозоны ✓                                        │
│   • Проверяет точки на вхождение ✓                             │
│   • ВСЁ!                                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Rules Engine                                                    │
│   • Знает ВСЕ правила ✓                                        │
│   • Маршрутизирует точки ✓                                     │
│   • Фильтрует "пустые" точки ✓                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 2. **Экономия ресурсов**

```
БЕЗ Rules Engine (10,000 точек/сек):
┌────────────────────────────────────────────────────────────────────────┐
│                                                                        │
│  gps-events (10K/сек)                                                 │
│       │                                                                │
│       ├──► Geozones Service: Загрузить правила для каждой точки!     │
│       │    10K × 1 запрос = 10K запросов к БД правил/сек              │
│       │                                                                │
│       ├──► Speed Service: Загрузить правила для каждой точки!        │
│       │    10K × 1 запрос = 10K запросов к БД правил/сек              │
│       │                                                                │
│       └──► Sensor Service: Загрузить правила для каждой точки!       │
│            10K × 1 запрос = 10K запросов к БД правил/сек              │
│                                                                        │
│  ИТОГО: 30K запросов к БД правил в секунду! 🔥                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

С Rules Engine (10,000 точек/сек):
┌────────────────────────────────────────────────────────────────────────┐
│                                                                        │
│  gps-events (10K/сек)                                                 │
│       │                                                                │
│       ▼                                                                │
│  Rules Engine: Загрузить правила (Redis Cache, 1 мс)                  │
│       │        10K × 1 cache lookup = 10K Redis GET/сек               │
│       │                                                                │
│       ├──► geozone-checks (~2K/сек) → Geozones Service                │
│       │    Только точки с правилами на геозоны!                       │
│       │                                                                │
│       └──► alerts (~100/сек) → Kafka                                  │
│            Скорость/датчики проверены прямо в Rules Engine            │
│                                                                        │
│  ИТОГО: 10K Redis GET + 2K Kafka send = минимальная нагрузка ✓       │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

#### 3. **Гибкость добавления новых типов правил**

```scala
// Rules Engine — добавить новый тип правила = 1 case
def processRule(rule: Rule, event: GpsEvent): Option[Action] = rule match {
  case GeozoneRule(ids) => 
    Some(SendToKafka("geozone-checks", event))
    
  case SpeedRule(limit) if event.speed > limit => 
    Some(SendToKafka("alerts", SpeedAlert(event)))
    
  case IdleRule(maxMinutes) if event.isIdle(maxMinutes) => 
    Some(SendToKafka("alerts", IdleAlert(event)))
    
  // Новое правило — просто добавить case!
  case FuelDrainRule(threshold) if event.fuelDrop > threshold =>
    Some(SendToKafka("alerts", FuelDrainAlert(event)))
    
  case _ => None
}
```

#### 4. **Централизованное управление**

```
┌─────────────────────────────────────────────────────────────────┐
│  Admin UI: Создать правило "Уведомить при въезде в геозону 5"  │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  Rules Engine API: POST /rules                                  │
│  {                                                              │
│    "vehicleId": "v123",                                        │
│    "type": "geozone_enter",                                    │
│    "params": { "geozoneId": 5 },                               │
│    "notify": ["email", "push"]                                 │
│  }                                                              │
└───────────────────────────────────┬─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│  Redis: rules:v123 → [{ type: "geozone_enter", ... }]          │
│                                                                 │
│  Мгновенно доступно без перезапуска сервисов!                 │
└─────────────────────────────────────────────────────────────────┘
```

### Аргументы ПРОТИВ Rules Engine:

1. **+1 сервис** = +1 точка отказа
2. **Latency** — дополнительный hop через Kafka
3. **Сложность** — ещё один компонент для деплоя

### Альтернатива: Rules Engine как библиотека (не сервис)

```scala
// Общая библиотека rules-core
trait RulesEngine {
  def getRulesForVehicle(vehicleId: String): List[Rule]
  def shouldProcess(rule: Rule, event: GpsEvent): Boolean
}

// Каждый сервис использует библиотеку
class GeozonesService(rules: RulesEngine) {
  def onGpsEvent(event: GpsEvent): Unit = {
    val geozoneRules = rules.getRulesForVehicle(event.vehicleId)
      .filter(_.isInstanceOf[GeozoneRule])
    
    if (geozoneRules.isEmpty) return  // Skip!
    
    // ... проверка геозон
  }
}
```

### Мой вердикт:

**Для MVP (первая версия):** Rules Engine **НЕ нужен**. 
- Делаем как в Stels — Geozones Service сам загружает правила
- Используем Guava/Redis cache для правил
- Когда упрёмся в производительность — выносим в отдельный сервис

**Для Production (10K+ машин):** Rules Engine **НУЖЕН**.
- Центральная точка маршрутизации
- Экономия ресурсов (не дублируем запросы к БД правил)
- Простое добавление новых типов правил

---

## 📊 Итоговая таблица: что где хранится

| Данные | Хранилище | Размер (10K машин) | TTL |
|--------|-----------|-------------------|-----|
| Правила уведомлений | PostgreSQL + Redis cache | ~50 MB | Redis: 5 мин |
| Spatial Grid | Redis | ~7 MB | 1 час |
| Состояние "машина → геозоны" | Redis | ~10 MB | 24 часа |
| Результаты проверок | Redis | ~50 MB | 30 сек |
| Геозоны (полигоны) | PostGIS | ~100 MB | - |
| GPS точки | TimescaleDB | ~10 GB/день | 90 дней |

---

## ⚙️ Конфигурируемые параметры

```yaml
# geozones-service.yaml
geozones:
  # Spatial Grid
  grid:
    enabled: true
    precision: 6  # Geohash precision (6 = ~1km)
    cache_ttl_sec: 3600
    
  # Coordinate rounding
  rounding:
    enabled: true
    precision: 0.0003  # ~30 meters
    
  # Result cache
  cache:
    enabled: true
    ttl_sec: 30
    max_size: 50000
    
  # Batching
  batch:
    enabled: true
    size: 100
    max_wait_ms: 500
    
  # Adaptive frequency
  adaptive:
    enabled: true
    idle_speed_kmh: 1
    idle_check_interval_sec: 300
    far_distance_m: 1000
    far_check_interval_sec: 30
    near_distance_m: 100
    near_check_interval_sec: 2
    default_check_interval_sec: 10
    
  # Anti-bounce (debounce)
  debounce:
    enabled: true
    confirm_time_sec: 5
```

---

**Дата:** 25 января 2026  
**Статус:** Ответы готовы ✅
