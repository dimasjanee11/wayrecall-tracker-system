# 📡 Legacy Stels API — Справочник

> **Дата:** 4 февраля 2026  
> **Источник:** `legacy-stels/monitoring/src/main/java/ru/sosgps/wayrecall/monitoring/web/`  
> **Протокол:** Ext Direct (ch.ralscha.extdirectspring) + REST

---

## 🔧 Технологии

- **Backend:** Spring MVC + Scala
- **API Protocol:** Ext Direct (batch RPC поверх HTTP POST)
- **Frontend:** ExtJS 4.2.1
- **Карты:** OpenLayers

---

## 📋 Ext Direct API (78 методов)

### MapObjects — Объекты на карте

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjects` | `ExtDirectStoreReadRequest` | `Iterator[Map]` | Список всех объектов пользователя |
| `getLonLat` | `selectedUids: Seq[String]` | `Seq[Map]` | Координаты выбранных объектов |
| `getApproximateLonLat` | `uid: String, time: Long` | `Map` | Приблизительная позиция на момент времени |
| `getSleeperInfo` | `uid: String` | `Seq[Map]` | Информация о "спящем блоке" |
| `getSensorNames` | `uid: String` | `Seq[Map]` | Список датчиков объекта |
| `regeocode` | `lon: Double, lat: Double` | `String` | Обратное геокодирование |
| `updateCheckedUids` | `selectedUids: Seq[String]` | `void` | Обновить выбранные объекты |
| `updateTargetedUids` | `selectedUids: Seq[String]` | `void` | Обновить отслеживаемые объекты |
| `getUserSettings` | — | `Map` | Настройки пользователя |
| `setUserSettings` | `settings: Map` | `void` | Сохранить настройки |
| `setHiddenUids` | `selectedUids: Seq[String]` | `void` | Скрыть объекты |
| `unsetHiddenUids` | `selectedUids: Seq[String]` | `void` | Показать объекты |
| `getUpdatedAfter` | `date: Date` | `Iterator[Map]` | Обновления после даты (polling) |

---

### GeozonesData — Геозоны CRUD

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjects` | `ExtDirectStoreReadRequest` | `Iterator[Map]` | Список геозон пользователя |
| `loadById` | `id: Int` | `Map` | Геозона по ID |
| `addGeozone` | `newZone: Map` | `Boolean` | Создать геозону |
| `editGeozone` | `geoZone: Map` | `Boolean` | Редактировать геозону |
| `delGeozone` | `id: Int` | `void` | Удалить геозону |
| `testPoint` | `lon, lat, speed, pwr_ext` | `Map` | Тест точки (в каких геозонах) |

**Формат геозоны:**
```json
{
  "id": 123,
  "name": "Склад №1",
  "ftColor": "#FF0000",
  "points": "[{\"x\":37.61,\"y\":55.75},{\"x\":37.62,\"y\":55.75}...]"
}
```

---

### EventsMessages — Уведомления/События

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjects` | `ExtDirectStoreReadRequest` | `Iterator[Map]` | История событий |
| `getUnreadUserMessagesCount` | — | `Int` | Количество непрочитанных |
| `updateEventsReadStatus` | `events: List, readStatus: Boolean` | `void` | Пометить прочитанными |
| `updateEventReadStatus` | `eventdata: Map` | `void` | Обновить статус события |
| `getLastEvent` | `uid: String` | `Map` | Последнее событие объекта |
| `getUpdatedAfter` | `date: Date` | `Map` | Новые события (polling) |
| `getMessageHash` | `text, msgType, time` | `String` | Хеш сообщения |

**Формат события:**
```json
{
  "eid": 12345,
  "uid": "o123456",
  "name": "Камаз-001",
  "text": "Вход в геозону: Склад №1",
  "time": 1706961234000,
  "type": "geozone_enter",
  "readStatus": false,
  "lon": 37.618,
  "lat": 55.751
}
```

---

### NotificationRules — Правила уведомлений

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjects` | `ExtDirectStoreReadRequest` | `Iterator[Map]` | Список правил |
| `addNotificationRule` | `newRule: Map` | `Map` | Создать правило |
| `updNotificationRule` | `newRule: Map` | `void` | Обновить правило |
| `delNotificationRule` | `ruleName: String` | `void` | Удалить правило |

**Формат правила:**
```json
{
  "name": "Превышение скорости",
  "type": "ntfSpeed",
  "allobjects": false,
  "showmessage": true,
  "messagemask": "Скорость {speed} км/ч",
  "email": "admin@example.com",
  "phone": "+79001234567",
  "params": {"maxSpeed": 90},
  "objects": ["o123", "o456"],
  "action": "none"
}
```

**Типы правил:**
- `ntfSpeed` — превышение скорости
- `ntfGeoZ` — вход/выход из геозоны
- `ntfData` — значение датчика
- `ntfStop` — долгая стоянка
- `ntfNoData` — нет данных

---

### ObjectsCommander — Команды устройствам

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `commandPasswordNeeded` | — | `Boolean` | Нужен ли пароль для команд |
| `sendBlockCommand` | `uid, block, password` | `void` | Заблокировать/разблокировать |
| `sendGetCoordinatesCommand` | `uid, password` | `void` | Запросить координаты |
| `sendRestartTerminalCommand` | `uid, password` | `void` | Перезагрузить терминал |

---

### EventedObjectCommander — Отложенные команды

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `sendBlockCommandAtDate` | `uid, block, password, date` | `void` | Блокировка по времени |
| `sendBlockAfterStop` | `uid, block, password` | `void` | Блокировка после остановки |
| `sendBlockAfterIgnition` | `uid, block, password` | `void` | Блокировка после зажигания |
| `countTasks` | `uid: String` | `Int` | Количество задач |
| `cancelTasks` | `uid: String` | `void` | Отменить задачи |

---

### PositionService — Позиции

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `getNearestPosition` | `uid, from, to, lon, lat, radius` | `Map` | Ближайшая позиция к точке |
| `getIndex` | `uid, from, cur` | `Map` | Количество точек в интервале |

---

### SensorsList — Датчики

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjects` | `ExtDirectStoreReadRequest` | `Seq[Map]` | Общие датчики для объектов |
| `getCommonTypes` | — | `Seq[Map]` | Типы датчиков |
| `getObjectSensorsCodenames` | `selectedUid: String` | `Seq[Map]` | Кодовые имена датчиков |

**Типы датчиков:**
- `sFuelL` — уровень топлива (л)
- `sFuelLP` — уровень топлива (%)
- `sTmp` — температура
- `sEngS` — обороты двигателя
- `sIgn` — зажигание
- `sPwr` — напряжение
- `sDist` — пробег

---

### ObjectSettings — Настройки объекта

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `loadObjectSettings` | `uid: String` | `Map` | Настройки объекта |
| `saveObjectSettings` | `uid, settings, params` | `void` | Сохранить настройки |
| `loadObjectSensors` | `uid: String` | `Seq[Map]` | Датчики объекта |
| `loadObjectMapSettings` | `uid: String` | `Map` | Настройки отображения на карте |

---

### MaintenanceService — Техобслуживание

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `saveSettings` | `uid, settings` | `void` | Сохранить настройки ТО |
| `getMaintenanceState` | `uid: String` | `Map` | Состояние ТО |
| `resetMaintenance` | `uid: String` | `Map` | Сбросить счётчик ТО |

---

### TimeZonesStore — Часовые пояса

| Метод | Параметры | Возвращает | Описание |
|-------|-----------|------------|----------|
| `getUserTimezone` | — | `String` | Часовой пояс пользователя |
| `loadObjects` | `ExtDirectStoreReadRequest` | `Iterator[Map]` | Список часовых поясов |

---

## 📊 Отчёты (Reports)

### Общий формат запроса
```json
{
  "uids": ["o123", "o456"],
  "from": "2026-02-01T00:00:00",
  "to": "2026-02-04T23:59:59"
}
```

| Контроллер | Метод | Описание |
|------------|-------|----------|
| `MovingReport` | `loadData` | Движение (интервалы) |
| `ParkingReport` | `loadData` | Стоянки |
| `FuelingReport` | `loadData` | Заправки/сливы |
| `GroupPathReport` | `loadData` | Маршрут группы |
| `GroupPathReport` | `getReportPerObject` | Статистика по объекту |
| `GroupPathReport` | `getObjectDayStatReport` | Дневная статистика |
| `MovingGroupReport` | `loadData` | Движение группы |
| `MovingGroupReport` | `getReportPerDay` | По дням |
| `MovementStatsReport` | `loadData` | Статистика движения |
| `AddressesReport` | `loadData` | Адреса посещений |
| `EventsReport` | `getData` | События за период |

---

## 🌐 REST Endpoints

### Экспорт отчётов

| Endpoint | Метод | Описание |
|----------|-------|----------|
| `/generatePDF/{repType}.pdf` | GET | PDF отчёт |
| `/generateXLS/{repType}.xls` | GET | Excel отчёт |
| `/generateCSV/{repType}.csv` | GET | CSV отчёт |
| `/export2PDF/report.pdf` | GET | Экспорт в PDF |
| `/export2XLS/report.xls` | GET | Экспорт в Excel |
| `/export2DOCX/report.docx` | GET | Экспорт в Word |

### Карты и изображения

| Endpoint | Метод | Описание |
|----------|-------|----------|
| `/reportMap` | GET | Статичная карта маршрута |
| `/staticimg/{uuid}.png` | GET | Статичное изображение |
| `/osm/{zoom}/{x}/{y}.png` | GET | OSM тайлы (прокси) |
| `/xychart/{repType}.png` | GET | График |

### Данные трека

| Endpoint | Метод | Параметры | Описание |
|----------|-------|-----------|----------|
| `/pathdata` | GET | `selected, from, to, type` | Данные трека |

**Типы (`type`):**
- `path` — границы трека (minlat, maxlat, minlon, maxlon)
- `grid` — точки с пагинацией
- `csv` — CSV экспорт
- `fuel` — данные топлива

### Прочее

| Endpoint | Метод | Описание |
|----------|-------|----------|
| `/localization.js` | GET | Локализация |
| `/recoverypassword` | GET | Восстановление пароля |
| `/senderror` | POST | Отправка ошибки |
| `/getnotifications` | GET | Уведомления (legacy) |
| `/blocktest` | POST | Тест блокировки |
| `/getobjectsdata` | GET | Данные объектов |
| `/getgroups` | GET | Группы объектов |

---

## 🔄 Real-time (Polling)

Stels использовал **long polling**, не WebSocket:

```javascript
// app/controller/MapObjects.js
serverRequest: function () {
    var self = this;
    eventsMessages.getUpdatedAfter(self.lastTimeUpdated, function (resp) {
        // Обработка новых событий
        self.lastTimeUpdated = resp.newTime;
        
        // Следующий запрос через 2 секунды
        setTimeout(function () {
            self.serverRequest();
        }, 2000);
    });
}
```

**Polling endpoints:**
- `eventsMessages.getUpdatedAfter(date)` — новые события
- `mapObjects.getUpdatedAfter(date)` — обновления объектов

---

## 🔐 Аутентификация

Spring Security + сессии:
- Логин через форму `/login`
- Сессия в cookie `JSESSIONID`
- Все Ext Direct вызовы требуют активной сессии

---

## 📝 Заметки для миграции

1. **Ext Direct → REST API** — заменить на стандартный REST
2. **Polling → WebSocket** — реализовать через WebSocket Service
3. **Координаты** — Stels использовал EPSG:900913 (Web Mercator), конвертировал в EPSG:4326
4. **Идентификаторы** — `uid` в формате `o{числовойId}` (например `o639670882911962921`)
5. **Даты** — ISO 8601 формат `yyyy-MM-dd'T'HH:mm:ss`

---

**Статус:** Справочник ✅
