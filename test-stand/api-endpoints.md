# 🌐 API Endpoints - TrackerGPS

Документация всех API эндпоинтов системы TrackerGPS.

---

## 🚗 Device Manager API

**Base URL:** `http://192.168.1.5:8081/api`

### Authentication
```
Header: X-API-Key: YOUR_API_KEY
```

### Devices

#### Получить список всех устройств
```http
GET /api/devices
```

**Response:**
```json
{
  "devices": [
    {
      "imei": "123456789012345",
      "name": "Truck #1",
      "protocol": "gt06",
      "vehicle_id": 1,
      "is_active": true,
      "last_seen": "2026-01-23T14:30:00Z"
    }
  ]
}
```

#### Получить устройство по IMEI
```http
GET /api/devices/:imei
```

**Example:**
```bash
curl -H "X-API-Key: YOUR_KEY" http://192.168.1.5:8081/api/devices/123456789012345
```

#### Зарегистрировать новое устройство
```http
POST /api/devices
Content-Type: application/json

{
  "imei": "123456789012345",
  "name": "New Device",
  "protocol": "gt06",
  "vehicle_id": 1
}
```

#### Обновить устройство
```http
PUT /api/devices/:imei
Content-Type: application/json

{
  "name": "Updated Name",
  "is_active": false
}
```

#### Удалить устройство
```http
DELETE /api/devices/:imei
```

---

### Commands

#### Отправить команду на устройство
```http
POST /api/commands
Content-Type: application/json

{
  "imei": "123456789012345",
  "command_type": "locate",
  "command_data": {
    "interval": 30
  }
}
```

**Response:**
```json
{
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "created_at": "2026-01-23T14:30:00Z"
}
```

#### Получить статус команды
```http
GET /api/commands/:command_id
```

**Response:**
```json
{
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "imei": "123456789012345",
  "command_type": "locate",
  "status": "acknowledged",
  "sent_at": "2026-01-23T14:30:05Z",
  "ack_at": "2026-01-23T14:30:10Z"
}
```

#### История команд устройства
```http
GET /api/devices/:imei/commands?limit=10&offset=0
```

---

## 📍 GPS Positions API (History Writer)

**Base URL:** `http://192.168.1.5:8082/api`

### Positions

#### Получить последнюю позицию устройства
```http
GET /api/positions/:imei/last
```

**Response:**
```json
{
  "time": "2026-01-23T14:30:00Z",
  "imei": "123456789012345",
  "vehicle_id": 1,
  "latitude": 55.7558,
  "longitude": 37.6173,
  "altitude": 150.5,
  "speed": 60.5,
  "heading": 180,
  "satellites": 12,
  "is_moving": true,
  "is_valid": true
}
```

#### История позиций за период
```http
GET /api/positions/:imei/history?from=2026-01-23T00:00:00Z&to=2026-01-23T23:59:59Z
```

**Query Parameters:**
- `from` - начало периода (ISO 8601)
- `to` - конец периода (ISO 8601)
- `limit` - макс. количество записей (default: 1000)
- `moving_only` - только движение (true/false)

**Response:**
```json
{
  "positions": [
    {
      "time": "2026-01-23T14:30:00Z",
      "latitude": 55.7558,
      "longitude": 37.6173,
      "speed": 60.5,
      "heading": 180
    }
  ],
  "total": 1234,
  "returned": 1000
}
```

#### Треk за день
```http
GET /api/positions/:imei/track?date=2026-01-23
```

**Response:** GeoJSON LineString
```json
{
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [37.6173, 55.7558],
      [37.6180, 55.7560],
      [37.6185, 55.7562]
    ]
  },
  "properties": {
    "imei": "123456789012345",
    "date": "2026-01-23",
    "total_distance_km": 45.3,
    "total_duration_hours": 3.5
  }
}
```

---

## 📊 Statistics API

#### Статистика по устройству за период
```http
GET /api/statistics/:imei?from=2026-01-01&to=2026-01-31
```

**Response:**
```json
{
  "imei": "123456789012345",
  "period": {
    "from": "2026-01-01T00:00:00Z",
    "to": "2026-01-31T23:59:59Z"
  },
  "stats": {
    "total_distance_km": 1250.5,
    "total_duration_hours": 85.3,
    "avg_speed_kmh": 42.5,
    "max_speed_kmh": 95.0,
    "positions_count": 12345,
    "moving_time_hours": 65.2,
    "idle_time_hours": 20.1
  }
}
```

---

## 🗺️ Geozone API (будущее)

**Base URL:** `http://192.168.1.5:8083/api`

### Geozones

#### Список всех геозон
```http
GET /api/geozones
```

#### Создать геозону
```http
POST /api/geozones
Content-Type: application/json

{
  "name": "Warehouse Moscow",
  "zone_type": "circular",
  "center": {
    "latitude": 55.7558,
    "longitude": 37.6173
  },
  "radius_meters": 500
}
```

#### События геозон
```http
GET /api/geozone-events?vehicle_id=1&from=2026-01-23T00:00:00Z
```

---

## 🔔 Notifications API (будущее)

**Base URL:** `http://192.168.1.5:8084/api`

### Notifications

#### Получить уведомления
```http
GET /api/notifications?user_id=1&unread=true
```

#### Отметить прочитанным
```http
PUT /api/notifications/:notification_id/read
```

---

## 📈 Metrics API (Prometheus)

**Base URL:** `http://192.168.1.5:9090/api/v1`

### Queries

#### Количество GPS событий в секунду
```http
GET /api/v1/query?query=rate(gps_events_total[5m])
```

#### Использование памяти сервисами
```http
GET /api/v1/query?query=container_memory_usage_bytes{name=~"tracker-.*"}
```

---

## 🔌 WebSocket API (будущее)

**URL:** `ws://192.168.1.5:8085/ws`

### Real-time Position Updates

```javascript
const ws = new WebSocket('ws://192.168.1.5:8085/ws');

// Subscribe to device updates
ws.send(JSON.stringify({
  type: 'subscribe',
  imei: '123456789012345'
}));

// Receive updates
ws.onmessage = (event) => {
  const position = JSON.parse(event.data);
  console.log(position);
};
```

---

## 🧪 Testing / Debug Endpoints

### Health Checks

```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "0.1.0",
  "uptime_seconds": 3600
}
```

### Readiness

```http
GET /ready
```

### Metrics (Prometheus format)

```http
GET /metrics
```

---

## 📝 cURL Examples

### Получить список устройств
```bash
curl -H "X-API-Key: YOUR_KEY" \
  http://192.168.1.5:8081/api/devices
```

### Отправить команду
```bash
curl -X POST \
  -H "X-API-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"imei":"123456789012345","command_type":"locate"}' \
  http://192.168.1.5:8081/api/commands
```

### История позиций
```bash
curl "http://192.168.1.5:8082/api/positions/123456789012345/history?from=2026-01-23T00:00:00Z&to=2026-01-23T23:59:59Z&limit=100"
```

---

## 🔒 Rate Limiting

- **Device Manager:** 100 req/min per API key
- **History Writer:** 1000 req/min (read-only)
- **WebSocket:** 10 connections per client

---

## ⚠️ Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid request",
  "message": "Missing required field: imei"
}
```

### 401 Unauthorized
```json
{
  "error": "Unauthorized",
  "message": "Invalid or missing API key"
}
```

### 404 Not Found
```json
{
  "error": "Not found",
  "message": "Device with IMEI 123456789012345 not found"
}
```

### 429 Too Many Requests
```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests, try again in 60 seconds"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error",
  "message": "An unexpected error occurred"
}
```

---

## 📚 Postman Collection

Импортируйте коллекцию для Postman:
```
test-stand/postman/TrackerGPS.postman_collection.json
```

---

## 🔗 Полезные ссылки

- **Swagger UI:** http://192.168.1.5:8081/swagger (если включен)
- **Grafana Dashboards:** http://192.168.1.5:3000
- **Prometheus Targets:** http://192.168.1.5:9090/targets
- **Kafka UI:** http://192.168.1.5:8080 (если установлен)
