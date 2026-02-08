# 📡 Мониторинг — API Контракт (Legacy Stels)

> **Дата:** 8 февраля 2026  
> **Источник:** legacy-stels/monitoring — ExtJS 4.2.1 + Spring + Ext.Direct  
> **Назначение:** Полный каталог backend API мониторинговой веб-панели (пользовательская часть)  
> **Связанный документ:** [BILLING_API_CONTRACT.md](BILLING_API_CONTRACT.md) — API биллинг-панели (админка)

---

## 📋 Содержание

1. [Как работает Ext.Direct](#как-работает-extdirect)
2. [Объекты на карте (MapObjects)](#1-mapobjects--объекты-на-карте)
3. [Группированные объекты (GroupedMapObjects)](#2-groupedmapobjects--группированные-объекты)
4. [Настройки объектов (ObjectSettings)](#3-objectsettings--настройки-объектов)
5. [Иконки объектов (ObjectImagesStore)](#4-objectimagesstore--иконки-объектов)
6. [Команды (ObjectsCommander)](#5-objectscommander--команды-трекеру)
7. [Отложенные команды (EventedObjectCommander)](#6-eventedobjectcommander--отложенные-команды)
8. [Пользователь (UserInfo)](#7-userinfo--информация-о-пользователе)
9. [Геозоны (GeozonesData)](#8-geozonesdata--геозоны)
10. [Позиции (PositionService)](#9-positionservice--позиции)
11. [Уведомления (EventsMessages)](#10-eventsmessages--уведомления)
12. [Правила уведомлений (NotificationRules)](#11-notificationrules--правила-уведомлений)
13. [Техобслуживание (MaintenanceService)](#12-maintenanceservice--техобслуживание)
14. [Датчики (SensorsList)](#13-sensorslist--датчики)
15. [Часовые пояса (TimeZonesStore)](#14-timezonesstore--часовые-пояса)
16. [Отчёты](#15-отчёты)
17. [Биллинг-сторы](#16-биллинг-сторы)
18. [Прочие сервисы](#17-прочие-сервисы)
19. [REST/HTTP контроллеры](#18-resthttp-контроллеры)
20. [Сводная таблица](#сводная-таблица)

---

## Как работает Ext.Direct

Аннотация `@ExtDirectService` (= Spring `@Service`) регистрирует bean с camelCase-именем класса.  
JS-клиент вызывает `beanName.methodName(...)` через `Ext.app.REMOTING_API`.

Типы методов:
- **STORE_READ** — загрузка данных для Ext.data.Store (пагинация, фильтры)
- **SIMPLE** — обычный RPC-вызов
- **FORM_POST** — загрузка файлов (multipart)

Polling: каждые **2 секунды** вызывается `getUpdatedAfter()` для MapObjects и EventsMessages.

---

## 1. MapObjects — Объекты на карте

**Класс:** `MapObjects` | **Bean:** `mapObjects`  
**Store:** `"MapObjects"` | **idProperty:** `"uid"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Загрузка всех трекеров пользователя с позициями, статусами, флагами checked/hidden/targeted |
| `getSleeperInfo` | `uid: String` | SIMPLE | Информация о «спящем блоке» оборудования |
| `getLonLat` | `selectedUids: Seq[String]` | SIMPLE | Последние координаты (lon/lat/speed/course) для выбранных объектов |
| `getApproximateLonLat` | `uid: String, time: Long` | SIMPLE | Приблизительные координаты на заданный момент времени |
| `getSensorNames` | `uid: String` | SIMPLE | Список датчиков объекта (code, name, show) |
| `regeocode` | `lon: Double, lat: Double` | SIMPLE | Обратное геокодирование координат → адрес |
| `updateCheckedUids` | `selectedUids: Seq[String]` | SIMPLE | Обновление списка выбранных объектов |
| `updateTargetedUids` | `selectedUids: Seq[String]` | SIMPLE | Обновление списка целевых объектов |
| `getUserSettings` | — | SIMPLE | Настройки карты пользователя |
| `setUserSettings` | `settings: Map` | SIMPLE | Сохранение настроек карты |
| `setHiddenUids` | `selectedUids: Seq[String]` | SIMPLE | Скрыть объекты на карте |
| `unsetHiddenUids` | `selectedUids: Seq[String]` | SIMPLE | Показать скрытые объекты |
| `getUpdatedAfter` | `timestamp: Long` | SIMPLE | **Polling (2 сек):** обновления объектов после указанного момента |

---

## 2. GroupedMapObjects — Группированные объекты

**Класс:** `GroupedMapObjects extends MapObjects` | **Bean:** `groupedMapObjects`  
**Store:** `"GroupedMapObjects"` | **idProperty:** `"_id"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Объекты, сгруппированные по пользовательским группам (поле `groupName`) |

> Наследует **все 13 методов** из MapObjects.

---

## 3. ObjectSettings — Настройки объектов

**Класс:** `ObjectSettings` | **Bean:** `objectSettings`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `saveObjectSettings` | `uid: String, settings: Map, params: Map` | SIMPLE | Сохранение настроек (поездки, вид, топливо, датчики, customName) |
| `loadObjectSettings` | `uid: String` | SIMPLE | Загрузка настроек (фильтрация по правам: fuel/view/trips) |
| `loadObjectSensors` | `uid: String` | SIMPLE | Конфигурация датчиков объекта |
| `loadObjectMapSettings` | `uid: String` | SIMPLE | Настройки отображения на карте (imgSource, imgRotate, imgArrow) |

---

## 4. ObjectImagesStore — Иконки объектов

**Класс:** `ObjectImagesStore` | **Bean:** `objectImagesStore`  
**Store:** `"ObjectImages"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Список PNG-иконок автомобилей (name, src, size) из `images/cars/` |

---

## 5. ObjectsCommander — Команды трекеру

**Класс:** `ObjectsCommander` | **Bean:** `objectsCommander`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `commandPasswordNeeded` | — | SIMPLE | Проверка, требуется ли пароль для отправки команд |
| `sendGetCoordinatesCommand` | `uid: String, password: String` | SIMPLE | SMS-команда «Получить координаты» |
| `sendRestartTerminalCommand` | `uid: String, password: String` | SIMPLE | SMS-команда «Перезагрузка терминала» |
| `sendBlockCommand` | `uid: String, block: Boolean, password: String` | SIMPLE | Блокировка/разблокировка двигателя через SMS/GPRS |

---

## 6. EventedObjectCommander — Отложенные команды

**Класс:** `EventedObjectCommander` | **Bean:** `eventedObjectCommander`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `sendBlockCommandAtDate` | `uid, block, password, date0: Long` | SIMPLE | Отложенная блокировка по расписанию (timer) |
| `sendBlockAfterStop` | `uid, block, password` | SIMPLE | Блокировка при остановке (speed ≤ 0) |
| `sendBlockAfterIgnition` | `uid, block, password` | SIMPLE | Блокировка при выключении зажигания |
| `countTasks` | `uid: String` | SIMPLE | Количество запланированных задач |
| `cancelTasks` | `uid: String` | SIMPLE | Отмена всех запланированных задач |

---

## 7. UserInfo — Информация о пользователе

**Класс:** `UserInfo` (Java) | **Bean:** `userInfo`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `getWarnings` | — | SIMPLE | Предупреждения при входе (блокировки, низкий баланс) |
| `getAccount` | — | SIMPLE | Основной лицевой счёт пользователя |
| `getBalanceDisplayRules` | — | SIMPLE | Правила отображения баланса (showbalance, showfeedetails) |
| `getContactInfo` | — | SIMPLE | Контактные данные (email, phone) |
| `getClusteringEnabled` | — | SIMPLE | Включена ли кластеризация на карте |
| `getSettings` | — | SIMPLE | Настройки пользователя (кластеризация, уведомления, маркеры) |
| `updateSettings` | `settings: Map` | SIMPLE | Обновление настроек (пароль, email, phone, timezone). Возвращает `"SUCCESS"` / `"WRONG PASSWORD"` |
| `canChangePassword` | — | SIMPLE | Может ли пользователь менять пароль |

---

## 8. GeozonesData — Геозоны

**Класс:** `GeozonesData` | **Bean:** `geozonesData`  
**Store:** `"GeozonesData"` | **idProperty:** `"id"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Все геозоны пользователя (id, name, ftColor, points) |
| `loadById` | `id: Int` | SIMPLE | Одна геозона по ID |
| `addGeozone` | `name, ftColor, points` | SIMPLE | Создание геозоны. Возвращает true/false |
| `editGeozone` | `id, name, ftColor, points` | SIMPLE | Редактирование геозоны |
| `delGeozone` | `id: Int` | SIMPLE | Удаление геозоны |
| `testPoint` | `lon, lat` | SIMPLE | Тест попадания точки в геозоны (debug) |

---

## 9. PositionService — Позиции

**Класс:** `PositionService` | **Bean:** `positionService`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `getNearestPosition` | `uid, from: Date, to: Date, lon, lat, radius` | SIMPLE | Ближайшая GPS-позиция к точке во временном диапазоне |
| `getIndex` | `uid, from: Date, cur: Date` | SIMPLE | Количество GPS-позиций за период `{n: count}` |

---

## 10. EventsMessages — Уведомления

**Класс:** `EventsMessages` | **Bean:** `eventsMessages`  
**Store:** `"EventsMessages"` | **idProperty:** `"eid"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | `uids, period/unread, from/to` | STORE_READ | Загрузка событий/уведомлений с фильтрами |
| `getUnreadUserMessagesCount` | — | SIMPLE | Количество непрочитанных уведомлений |
| `updateEventsReadStatus` | `eids: Seq, read: Boolean` | SIMPLE | Массовое обновление статуса прочитанности |
| `updateEventReadStatus` | `eid, read: Boolean` | SIMPLE | Обновление одного события |
| `getLastEvent` | `uid: String` | SIMPLE | Последнее событие объекта (за 7 дней) |
| `getUpdatedAfter` | `timestamp: Long` | SIMPLE | **Polling (2 сек):** новые уведомления + флаг `{newTime, data[], reload}` |
| `getMessageHash` | `message` | SIMPLE | Хеш сообщения для идемпотентности |

---

## 11. NotificationRules — Правила уведомлений

**Класс:** `NotificationRules` | **Bean:** `notificationRules`  
**Store:** `"NotificationRules"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Правила уведомлений (name, type, objects, params, action, email, phone) |
| `addNotificationRule` | `rule: Map` | SIMPLE | Создание правила |
| `delNotificationRule` | `ruleName: String` | SIMPLE | Удаление правила по имени |
| `updNotificationRule` | `newRule: Map` | SIMPLE | Обновление правила |

---

## 12. MaintenanceService — Техобслуживание

**Класс:** `MaintenanceService` | **Bean:** `maintenanceService`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `saveSettings` | `uid, settings: Map` | SIMPLE | Настройки ТО (пробег, моточасы, время) |
| `getMaintenanceState` | `uid: String` | SIMPLE | Состояние ТО (distanceUntil, motoUntil, timeUntil, intervals, enabled) |
| `resetMaintenance` | `uid, type` | SIMPLE | Сброс счётчиков ТО. Возвращает `{requireMaintenance: bool}` |

---

## 13. SensorsList — Датчики

**Класс:** `SensorsList` | **Bean:** `sensorsList`  
**Store:** `"SensorsList"` | **idProperty:** `"code"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | `uids: Seq[String]` | STORE_READ | Общие (пересечение) датчики для списка объектов |
| `getCommonTypes` | — | SIMPLE | Справочник типов датчиков (19 типов: топливо, температура, скорость...) |
| `getObjectSensorsCodenames` | `uid: String` | SIMPLE | Кодовые имена датчиков объекта |

---

## 14. TimeZonesStore — Часовые пояса

**Класс:** `TimeZonesStore` | **Bean:** `timeZonesStore`  
**Store:** `"Timezones"` | **idProperty:** `"id"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | (ExtDirect store params) | STORE_READ | Список часовых поясов (id, name, offset) |
| `getUserTimezone` | — | SIMPLE | Текущий часовой пояс пользователя |

---

## 15. Отчёты

Все отчёты — это Ext.Direct Store с методом `loadData` (STORE_READ).  
Параметры: `uid(s)`, `from: Date`, `to: Date` + специфичные для типа.

### 15.1 MovementStatsReport — Общая статистика

**Bean:** `movementStatsReport` | **Store:** `"MovementStats"`

Поля: пробег, остановки, стоянки, макс. скорость, моточасы, расход топлива.

### 15.2 GroupMovementStatsReport — Групповая статистика

**Bean:** `groupMovementStatsReport` | **Store:** `"GroupMovementStats"`

Суммарные данные движения по группе объектов.

### 15.3 MovingReport — Поездки

**Bean:** `movingReport` | **Store:** `"MovingReport"` | **idProperty:** `"datetime"`

Поля: начало, конец, длительность, дистанция, макс. скорость, адреса начала/конца.

### 15.4 TripReport — Поездки + стоянки (deprecated)

**Bean:** `tripReport` | **Store:** `"TripReport"` | **idProperty:** `"datetime"`

Поля: тип (поездка/стоянка), начало, конец, длительность, дистанция.

### 15.5 GroupMovingReport — Групповой отчёт о движении

**Bean:** `groupMovingReport` | **Store:** `"GroupMovingReport"` | **idProperty:** `"_id"`

Отчёт о движении по объектам в группе.

### 15.6 ParkingReport — Стоянки

**Bean:** `parkingReport` | **Store:** `"ParkingReport"` | **idProperty:** `"datetime"`

Поля: datetime, interval, regeo (адрес), isSmall.

### 15.7 FuelingReport — Заправки/сливы

**Bean:** `fuelingReport` | **Store:** `"FuelingReport"` | **idProperty:** `"datetime"`

Поля: datetime, isFueling, startVal, endVal, volume, regeo.

### 15.8 EventsReport — События объекта

**Bean:** `eventsReport` | **Store:** `"EventsReport"` | **idProperty:** `"num"`

Поля: time, type, message, additionalData (lon/lat).

### 15.9 GroupPathReport — Табличный групповой отчёт

**Bean:** `groupPathReport` | **Store:** `"GroupPathReport"` | **idProperty:** `"_id"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadData` | `uids, from, to` | STORE_READ | Статистика за период по каждому объекту группы |
| `getReportPerObject` | `uid, from, to` | SIMPLE | Подробные GPS-точки (lon, lat, speed, regeo, devdata) |
| `getObjectDayStatReport` | `uid, from, to` | SIMPLE | Посуточная статистика (дистанция, стоянки, движение) |

### 15.10 MovingGroupReport — Посуточная агрегация

**Bean:** `movingGroupReport` | **Store:** `"MovingGroupReport"` | **idProperty:** `"sDate"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadData` | `uid, from, to` | STORE_READ | Посуточная агрегация: стоянки/движение, дистанция, скорость |
| `getReportPerDay` | `uid, date` | SIMPLE | Детальный отчёт по дням (стоянки + движения с координатами) |

### 15.11 AddressesReport — Адреса

**Bean:** `addressesReport` | **Store:** `"AddressesReport"` | **idProperty:** `"num"`

Поля: date, time, address, lon, lat — уникальные адреса за период.

---

## 16. Биллинг-сторы

### NotificationPaymentList — Платежи за SMS

**Bean:** `notificationPaymentList` | **Store:** `"notificationPaymentList"` | **idProperty:** `"num"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | `month: String` | STORE_READ | Платежи за SMS (user, phone, fee, time, comment). Фильтр по месяцу |

### SubscriptionFeeList — Детализация абонентской платы

**Bean:** `subscriptionFeeList` | **Store:** `"SubscriptionFeeList"` | **idProperty:** `"uid"`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `loadObjects` | `month: String` | STORE_READ | Детализация (objectName, eqCount, fullFee, firstDate, lastDate). Фильтр по месяцу |

---

## 17. Прочие сервисы

### ErrorReporter — Логирование ошибок

**Bean:** `errorReporter` | Также `@Controller`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `reportError` | `message: String` | SIMPLE (ExtDirect) | Логирование ошибки с клиента |

> Также HTTP: `GET /senderror?message=...`

### DataFileLoader — Загрузка файлов

**Bean:** `dataFileLoader`

| Метод | Параметры | Тип | Назначение |
|-------|-----------|-----|------------|
| `getUploadedFileData` | `dataFile: MultipartFile` | FORM_POST | Загрузка CSV для калибровки датчиков (x,y координаты) |

---

## 18. REST/HTTP контроллеры

### CommandsEndpoint (Basic Auth)

| Endpoint | Метод | Назначение |
|----------|-------|------------|
| `GET /getnotifications` | HTTP | Имя пользователя (для push-уведомлений) |
| `POST /blocktest` | HTTP | Блокировка объекта (uid, block, password) |

### ReportGenerator — Экспорт отчётов

| Endpoint | Параметры | Назначение |
|----------|-----------|------------|
| `GET /generatePDF/{repType}.pdf` | uid, from, to | PDF одного отчёта |
| `GET /generateXLS/{repType}.xls` | uid, from, to | XLS одного отчёта |
| `GET /generateCSV/{repType}.csv` | uid, from, to | CSV одного отчёта |
| `GET /export2PDF/report.pdf` | uid, from, to, repList | Пакетный PDF |
| `GET /export2XLS/report.xls` | uid, from, to, repList | Пакетный XLS |
| `GET /export2DOCX/report.docx` | uid, from, to, repList | Пакетный DOCX |
| `GET /xychart/{repType}.png` | uid, from, to, sensorName | График (PNG) — скорость/топливо/датчик |

### StateReport (Basic Auth, deprecated)

| Endpoint | Назначение |
|----------|------------|
| `GET /getobjectsdata` | Все объекты с последними позициями и датчиками |
| `GET /getgroups` | Redirect → `/api/getgroups` |

### PasswordRecoveryController

| Endpoint | Назначение |
|----------|------------|
| `POST /recoverypassword` | Восстановление пароля по email |

### LocalizationManager

| Endpoint | Назначение |
|----------|------------|
| `GET /localization.js` | JS-файл с переводами |
| `GET /localization/ext-lang.js` | Локализация ExtJS |
| `GET /localization/openlayers-lang.js` | Локализация OpenLayers |
| `GET /localization/{mapType}` | Redirect к API карт с локалью |

### PathDataServlet (`/pathdata`)

| Параметр `data=` | Назначение |
|-------------------|------------|
| `speedgraph` | CSV графика скорости (time, speed) |
| `sensors` | CSV данных датчиков (time, values...) |
| `fuelgraph` | CSV графика топлива (time, fuel, speed, urban) |

### RotateServlet (`/rotate`)

| Параметр | Назначение |
|----------|------------|
| `angle, image` | Поворот иконки автомобиля на заданный угол |

### ReportStatsCollector (`/ReportStats`)

| Параметр | Назначение |
|----------|------------|
| `reportType, target, from, to` | Статистика просмотра отчётов |

---

## Сводная таблица

| Категория | Ext.Direct методов | REST эндпоинтов |
|-----------|-------------------|----------------|
| Объекты на карте | 13 + 1 (grouped) | — |
| Настройки объектов | 4 + 1 store | — |
| Команды | 4 + 5 (evented) | 2 |
| Пользователь | 8 | 1 |
| Геозоны | 6 | — |
| Позиции | 2 | — |
| Уведомления | 7 + 4 (rules) | — |
| ТО | 3 | — |
| Датчики | 3 | — |
| Отчёты | 12 STORE_READ + 3 SIMPLE | 8 (PDF/XLS/CSV/PNG) |
| Биллинг-сторы | 2 | — |
| Прочие | 3 (timezone, error, file) | 6 (localization, stats, path, rotate) |
| **ИТОГО** | **~76 методов** | **~17 эндпоинтов** |

---

## 🔗 Связь с новым проектом

| Legacy (Ext.Direct) | Новый сервис | Формат нового API |
|---------------------|-------------|-------------------|
| `mapObjects.*` | device-manager + connection-manager | REST + WebSocket |
| `objectSettings.*` | device-manager | REST |
| `objectsCommander.*` | device-manager (Redis queue) | REST + Redis ZSET |
| `userInfo.*` | auth-service + user-service | REST + JWT |
| `geozonesData.*` | geozones-service | REST |
| `eventsMessages.*` | notification-service | REST + WebSocket |
| `notificationRules.*` | notification-service + rule-checker | REST |
| `maintenanceService.*` | maintenance-service | REST |
| `sensorsList.*` | sensors-service | REST |
| `*Report.*` | analytics-service + history-writer | REST |
| `/pathdata` servlet | analytics-service | REST |
| `/generate*` reports | analytics-service | REST (export) |

---

> **Версия:** 1.0  
> **Дата создания:** 8 февраля 2026  
> **Автор:** AI Agent (GitHub Copilot)  
> **См. также:** [BILLING_API_CONTRACT.md](BILLING_API_CONTRACT.md)
