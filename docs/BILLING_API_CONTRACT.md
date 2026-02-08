# 📋 Billing API Contract — Полный список обращений к бэкенду

> Извлечено из legacy-stels. Все вызовы через **Ext.Direct** (JSON-RPC) + HTTP + WebSocket (Atmosphere).

---

## Оглавление

1. [Ext.Direct RPC методы](#1-extdirect-rpc-методы)
2. [Ext.Direct Store CRUD сервисы](#2-extdirect-store-crud-сервисы)
3. [HTTP эндпоинты](#3-http-эндпоинты)
4. [WebSocket (Atmosphere)](#4-websocket-atmosphere)
5. [Аутентификация](#5-аутентификация)

---

## 1. Ext.Direct RPC методы

> Протокол: `POST /EDS/router` с JSON-RPC payload.  
> Формат запроса: `{ action: "serviceName", method: "methodName", data: [...args], type: "rpc", tid: N }`

### 1.1 loginService (LoginService.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `getLogin()` | — | `String` | Имя текущего залогиненного пользователя |
| `logout(request, response)` | HttpServlet* (авто) | `void` | Выход, очистка cookies и security context |

### 1.2 rolesService (RolesService.scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `checkAdminRole()` | — | `Boolean` | Является ли текущий пользователь админом |
| `checkChangeRoleAuthority()` | — | `Boolean` | Есть ли право ChangeRoles + admin |
| `getUserAuthorities()` | — | `Array[String]` | Список прав текущего пользователя |
| `getAvailableUserTypes(userName)` | `String` | `Seq[Map]` | Доступные типы юзеров (admin/superuser/user/servicer) |
| `updateUserRole(data)` | `Map[String, Object]` | `Map` | Обновить роль пользователя (userId, templateId, authorities) |
| `getUserRole(userId)` | `String` | `Map[String, AnyRef]` | Получить роль пользователя по userId |
| `update(data)` | `Map[String, Object]` | — | Обновить шаблон роли (_id, name, authorities) |

### 1.3 accountData (AccountData.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `updateData(submitMap, contractCount)` | `Map<String,Object>`, `Integer` | `Map` с code/msg/accountId | Создание или обновление аккаунта (CQRS: AccountCreateCommand / AccountDataSetCommand) |
| `loadData(accountId)` | `String` | `Map<String,Object>` | Загрузка полных данных аккаунта по ID |

### 1.4 objectData (ObjectData.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `updateOnlyObjectData(submitMap)` | `Map<String,Serializable>` | `Map` с uid | Обновить данные объекта (без оборудования) |
| `updateData(submitMap)` | `Map<String,Serializable>` | `Map` с uid | Создание/обновление объекта + оборудование (CQRS: ObjectCreateCommand / ObjectDataSetCommand) |
| `loadData(uid)` | `String` | `Map<String,Object>` | Загрузка полных данных объекта по uid |
| `getObjectSleepers(uid)` | `String` | `List<DBObject>` | Список "спящих блоков" объекта |

### 1.5 equipmentData (EquipmentData.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `updateData(submitMap)` | `Map<String,Serializable>` | `Map` с code/msg/eqId | Создание/обновление оборудования (synchronized по IMEI) |
| `loadData(eqId)` | `String` | `Map<String,Object>` | Загрузка данных оборудования по ID |

### 1.6 equipmentTypesData (EquipmentTypesData.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `updateData(submitMap)` | `Map<String,Object>` | `Map` с code/msg/eqTypeId | Создание/обновление типа оборудования |
| `loadData(eqTypesId)` | `String` | `Map<String,Object>` | Загрузка данных типа оборудования по ID |
| `loadMarkByType(eqType)` | `String` | `List<Map>` | Список марок по типу оборудования |
| `loadModelByMark(eqType, eqMark)` | `String, String` | `List<Map>` | Список моделей по марке и типу |

### 1.7 configFileLoader (ConfigFileLoader.java)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `uploadFile(configFile, fwFile, forceConnection, IMEI)` | FORM_POST: MultipartFile × 2, boolean, String | `ExtDirectFormPostResult` | Загрузка конфиг/прошивки на оборудование по IMEI |

### 1.8 accountsStoreService (AccountsStoreService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `remove(ids, params)` | `Seq[String]`, `Map[String, Boolean]` | — | Удалить аккаунты (CQRS: AccountRemoveCommand) |
| `addToAccount(accid, objects)` | `String, Seq[String]` | — | Привязать объекты к аккаунту (перенос объектов + оборудования) |

### 1.9 accountInfo (AccountInfo — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `getObjectsStat(accountId)` | `String` | `Map[String, Int]` | Количество объектов аккаунта |
| `getEquiupmentsStat(accountId)` | `String` | `Map[String, Int]` | Количество оборудования аккаунта |

### 1.10 allObjectsService (AllObjectsService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `delete(maps)` | `Seq[String]` | — | Полное удаление объектов (ObjectDeleteCommand) |
| `remove(objectIds, deinstallEquipments)` | `Seq[String], Boolean` | — | В корзину (ObjectRemoveCommand), опционально снять оборудование |

### 1.11 accountsEquipmentService (AccountsEquipmentService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `modify(accountId, updatemaps, removemaps)` | `ObjectId, Seq[Map], Seq[Map]` | — | Привязать + отвязать оборудование от аккаунта |
| `update(accountId, maps)` | `ObjectId, Seq[Map]` | — | Привязать оборудование к аккаунту |
| `remove(accountId, maps)` | `ObjectId, Seq[Map]` | — | Отвязать оборудование от аккаунта (→ "Без Аккаунта") |

### 1.12 usersService (UsersService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `load(userId)` | `String` | `Map[String,Object]` | Загрузка пользователя по ID (с lastLoginDate, mainAccName и т.д.) |
| `update(map0)` | `Map[String, Object]` | `Map` с _id | Обновление пользователя (UserDataSetCommand) |
| `create(map0)` | `Map[String, Object]` | `Map` с _id | Создание пользователя (UserCreateCommand) |

### 1.13 usersPermissionsService (UsersPermissionsService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `getPermittedUsersCount(id, recType)` | `String, String` | `Integer` | Количество пользователей с правами на объект/аккаунт |
| `providePermissions(toUpdate, toRemove, recType, recId)` | `ArrayList, ArrayList, String, String` | — | Массовое назначение/удаление прав |

### 1.14 dealersService (DealersService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `dealerBlocking(id, block)` | `String, Boolean` | `Map` с status | Блокировка/разблокировка дилера |
| `getDealerParams(id)` | `String` | `Map` | Параметры дилера (baseTariff, balance, cost) |
| `updateDealerParams(submitMap)` | `Map[String, AnyRef]` | `Map` | Обновить baseTariff дилера (deprecated) |

### 1.15 retranslatorsListService (RetranslatorsListService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `remove(ids)` | `Seq[String]` | — | Удалить ретрансляторы по ID |

### 1.16 retranslatorsService (RetranslatorsService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `updateData(retranslatorId, name, host, port, protocol, data)` | `String, String, String, Int, String, Seq[Map]` | — | Обновить настройки ретранслятора + привязку объектов |

### 1.17 terminalMessagesService (TerminalMessagesService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `remove(uid, maps)` | `String, Seq[Map]` | — | Удалить отдельные GPS-точки по timemils |
| `removeInInterval(uid, from, to)` | `String, Date, Date` | — | Удалить GPS-точки в интервале |
| `reaggregate(uid, from)` | `String, Date` | — | Переагрегировать накопленные параметры с даты |

### 1.18 trackerMesService (TrackerMesService — Scala)

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `sendTeltonikaCMD(phone, command)` | `String, String` | — | SMS команда для Teltonika (login+pass+cmd) |
| `sendFMB920CMD(phone, command)` | `String, String` | — | SMS команда для Teltonika FMB920 |
| `sendRuptelaCMD(phone, command)` | `String, String` | — | SMS команда для Ruptela (pass+cmd) |
| `sendArnaviCMD(phone, command)` | `String, String` | — | SMS команда для Arnavi (pass+cmd) |
| `sendumkaCMD(phone, command)` | `String, String` | — | SMS команда для UMKA (только cmd) |
| `attachToWRC(phone)` | `String` | — | 3 SMS для перепрошивки на WRC (setparam APN, IP, port) |
| `ipAndPortToWRC(phone)` | `String` | — | 2 SMS для смены IP+порт на WRC |
| `sendSMSToTracker(phone, text)` | `String, String` | `Map` с sms данными | Отправить произвольный SMS на трекер |

### 1.19 userInfo (UserInfo.java) — для мониторинга, но доступен в billing

| Метод | Аргументы | Возврат | Описание |
|-------|-----------|---------|----------|
| `getWelcomeMessages()` | — | `List<String>` | Уведомления при входе (блокировки, низкий баланс) |
| `getUserMainAcc()` | — | `DBObject` | Основной аккаунт пользователя |
| `getDetailedBalanceRules()` | — | `Map` | Правила отображения баланса (showbalance, showfeedetails) |
| `getUserContacts()` | — | `Map` | Email и телефон пользователя |
| `isObjectsClustering()` | — | `boolean` | Включена ли кластеризация объектов |
| `getUserSettings()` | — | `Map` | Настройки: кластеризация, уведомления, маркеры |
| `updateUserSettings(settings)` | `Map<String,Object>` | `String` ("SUCCESS"/"WRONG PASSWORD") | Обновить настройки + пароль |
| `canChangePassword()` | — | `boolean` | Может ли пользователь менять пароль |

---

## 2. Ext.Direct Store CRUD сервисы

> Протокол: тот же `POST /EDS/router`, но с `ExtDirectMethodType.STORE_READ` / `STORE_MODIFY`.  
> Все сервисы наследуют `EDSStoreServiceDescriptor` и автоматически регистрируются как Ext.data.Store providers.  
> Формат: `{ action: "serviceName", method: "read/loadAll/...", data: [{ params, page, start, limit, sort, filter }] }`

### 2.1 AccountsData (AccountsStoreService — read)

- **JS Store name:** `AccountsData`
- **Модель:** `currency, plan, balance(float), _id, name, comment, cost, objectsCount, equipmentsCount, usersCount, status, paymentWay`
- **read(request)** — STORE_READ — Список аккаунтов (с фильтром по правам: admin видит все, superuser — только разрешённые)
- **Вычисляемые поля:** `cost` (из TariffPlans), `objectsCount`, `equipmentsCount`, `usersCount`

### 2.2 AccountsDataShort (AccountsStoreServiceShort — read)

- **JS Store name:** `AccountsDataShort`
- **Модель:** `_id, name`
- **read(request)** — STORE_READ — Краткий список аккаунтов (для комбобоксов)

### 2.3 ObjectsData (ObjectStoreManager — read)

- **JS Store name:** `ObjectsData`
- **Модель:** `uid, account, comment, accountId, _id, accountName, equipmentType, name, customName, cost, type, contract, marka, model, gosnumber, VIN, instplace, objnote, disabled`
- **read(request)** — STORE_READ — Объекты аккаунта (param: `accountId`)
- **Вычисляемые поля:** `cost` (из TariffPlans), `accountName`

### 2.4 ObjectsDataShort (ObjectStoreServiceShort — read)

- **JS Store name:** `ObjectsDataShort`
- **Модель:** `_id, name, customName, comment, uid, type, cost, subscriptionfee, marka, accountId, model, gosnumber, VIN, objnote, fuelPumpLock, ignitionLock, disabled`
- **read(request)** — STORE_READ — Краткий список объектов (param: `accountId`)

### 2.5 AllObjectsService (AllObjectsService — loadAllObjects)

- **JS Store name:** `AllObjectsService`
- **Модель:** `_id, account, accountName, name, customName, comment, uid, type, contract, cost, marka, model, gosnumber, VIN, instplace, blocked, ignition, objnote, latestmsg, latestmsgprotocol, sms, speed, satelliteNum, placeName, sleeper, sleepertime, trackerModel, disabled, radioUnit, eqIMEI, simNumber, eqMark, eqModel`
- **loadAllObjects(request)** — STORE_READ — Все объекты (с join терминалов, sleepers, GPS latest, фильтр прав)
- **Параметры:** `nonAccount` (исключить аккаунт), `query` (поиск)

### 2.6 AccountsEquipmentService (read)

- **JS Store name:** `AccountsEquipmentService`
- **Модель:** `_id, uid, objectid, objectName, accountId, eqOwner, eqRightToUse, eqSellDate, eqWork, eqWorkDate, eqNote, eqtype, eqMark, eqModel, eqSerNum, eqIMEI, eqFirmware, eqLogin, eqPass, simOwner, simProvider, simNumber, simICCID, simNote, instPlace`
- **read(request)** — STORE_READ — Оборудование аккаунта (param: `accountId`)

### 2.7 UsersService (loadAllUsers)

- **JS Store name:** `UsersService`
- **Модель:** `_id, name, comment, password, phone, email, lastLoginDate(date), lastAction(date), mainAccId, mainAccName, hascommandpass, commandpass, enabled, blockcause, canchangepass, showbalance, showfeedetails, userType, creator, hasBlockedMainAccount, hasObjectsOnBlockedAccount`
- **loadAllUsers(request)** — STORE_READ — Все пользователи (с lastAction из активных сессий)
- **remove(request, response, maps)** — STORE_MODIFY (destroy) — Удаление пользователей (UserDeleteCommand)

### 2.8 UserPermissionsService (UsersPermissionsService — loadAll)

- **JS Store name:** `UserPermissionsService`
- **Модель:** `_id, item_id, name, view, sleepersView, control, block, getCoords, restartTerminal, paramsView, paramsEdit, fuelSettings, sensorsSettings, uid, recordType, userId`
- **loadAll(request)** — STORE_READ — Права пользователя (param: `userId`), возвращает аккаунты + объекты с permissions
- **create(list)** — STORE_MODIFY (create) — Добавить право
- **update(list)** — STORE_MODIFY (update) — Обновить право
- **remove(request, response, list)** — STORE_MODIFY (destroy) — Удалить право

### 2.9 UserPermissionSelectionService (loadAll)

- **JS Store name:** `UserPermissionSelectionService`
- **Модель:** та же, что UserPermissionsService
- **loadAll(request)** — STORE_READ — Объекты/аккаунты, на которые ещё НЕ назначены права (param: `userId, ItemType`)

### 2.10 PermittedItemsService (loadAll)

- **JS Store name:** `PermittedItemsService`
- **Модель:** + `comment, inherited`
- **loadAll(request)** — STORE_READ — Пользователи с правами на конкретный объект/аккаунт (params: `oid, type, permitted`)

### 2.11 RolesService (readAll + remove)

- **JS Store name:** `RolesService`
- **Модель:** `_id, name, authorities`
- **readAll(request)** — STORE_READ — Все шаблоны ролей
- **remove(request, response, maps)** — STORE_MODIFY (destroy) — Удалить шаблон роли

### 2.12 TrackerMesService (read)

- **JS Store name:** `TrackerMesService`
- **Модель:** `_id, smsId, text, senderPhone, sendDate, targetPhone, status`
- **read(request)** — STORE_READ — SMS трекера (param: `phone`), с фильтрацией по интервалам удаления

### 2.13 TerminalMessagesService (read)

- **JS Store name:** `TerminalMessagesService`
- **Модель:** `regeo, speed, course, time(date), timemils, insertTime(date), devdata, coordinates`
- **read(request)** — STORE_READ — GPS-сообщения терминала (params: `uid, dateFrom, dateTo`), с пагинацией (start, limit)

### 2.14 RetranslatorsListService (loadAll)

- **JS Store name:** `RetranslatorsListService`
- **Модель:** `id, name, host, port, protocol`
- **loadAll(request)** — STORE_READ — Список ретрансляторов (из файлов конфигурации)

### 2.15 RetranslatorsService (loadAll)

- **JS Store name:** `RetranslatorsService`
- **Модель:** `id, name, uid, eqIMEI, accountName`
- **loadAll(request)** — STORE_READ — Объекты ретранслятора (param: `retranslatorId`)

### 2.16 DealersService (loadAll)

- **JS Store name:** `DealersService`
- **Модель:** `id, accounts, objects, equipments, block`
- **loadAll(request)** — STORE_READ — Список дилеров (количества по каждому)

### 2.17 DealerBalanceEntryTypes (loadData)

- **JS Store name:** `DealerBalanceEntryTypes`
- **Модель:** `type`
- **loadData()** — STORE_READ — Типы записей баланса дилера: `["-", "dailypay", "sms payment", "Зачислить"]`

### 2.18 DealersBalanceHistory (loadData)

- **JS Store name:** `DealersBalanceHistory`
- **Модель:** `id, type, ammount, timestamp, newbalance, comment`
- **loadData(request)** — STORE_READ — История баланса дилера (params: `accountId, typeFilter, dateFrom, dateTo`)

---

## 3. HTTP эндпоинты

> Помимо Ext.Direct RPC, billing использует обычные HTTP endpoints для специфических задач.

### 3.1 Аутентификация

| Метод | URL | Описание |
|-------|-----|----------|
| `POST` | `/billing/j_spring_security_check` | Spring Security form login. Params: `j_username, j_password, _spring_security_remember_me` |
| `GET` | `/billing/login.html` | Страница логина |
| `GET` | `/billing/index.html` | Главная страница (после авторизации) |

### 3.2 Ext.Direct Router

| Метод | URL | Описание |
|-------|-----|----------|
| `POST` | `/billing/EDS/router` | Единый маршрутизатор всех Ext.Direct вызовов (JSON-RPC) |
| `GET` | `/billing/EDS/api-debug.js` | Автогенерируемый JS — описание всех доступных действий/методов |

### 3.3 Экспорт данных

| Метод | URL | Описание |
|-------|-----|----------|
| `GET` | `/billing/EDS/gridDataExport` | Экспорт данных грида (GridDataExport.scala). Params: `gridName, format(xls/csv), dateFrom, dateTo, uid, accountId` |

### 3.4 Файловый загрузчик

| Метод | URL | Описание |
|-------|-----|----------|
| `GET` | `/billing/EDS/dataFileLoader` | Загрузка файлов (DataFileLoader.scala) |

### 3.5 Управление дилерами

| Метод | URL | Описание |
|-------|-----|----------|
| `POST` | `/billing/EDS/dealerbalanceChange` | Изменение баланса дилера (FORM_POST). Params: `accountId, amount, type, comment` |

### 3.6 Backdoor (вход под дилером / пользователем)

| Метод | URL | Описание |
|-------|-----|----------|
| `GET` | `/billing/EDS/monitoringbackdoor` | Войти в мониторинг под пользователем (param: userId). Только для admin+DealerBackdoor |
| `GET` | `/billing/EDS/dealerbackdoor` | Войти в биллинг дилера (param: dealerId). Только для admin+DealerBackdoor |

### 3.7 Права пользователя (JS)

| Метод | URL | Описание |
|-------|-----|----------|
| `GET` | `/billing/EDS/authorities.js` | JS-файл с правами текущего пользователя (UserAuthoritiesService) |

---

## 4. WebSocket (Atmosphere)

> Транспорт: Atmosphere Framework с fallback websocket → long-polling.  
> Endpoint: `pubsub/servermes`

### 4.1 Конфигурация (из app.js)

```javascript
{
  url: '/billing/pubsub/servermes',
  transport: 'websocket',
  fallbackTransport: 'long-polling',
  trackMessageLength: true,
  enableProtocol: true
}
```

### 4.2 Входящие события (Server → Client)

| Событие | Формат данных | Описание |
|---------|---------------|----------|
| `aggregateEvent` | `{ type: "aggregateEvent", ... }` | Обновление одного объекта в реальном времени |
| `aggregateEventBatch` | `{ type: "aggregateEventBatch", data: [...] }` | Пакет обновлений объектов (обрабатывается блоками по 10 с requestAnimationFrame) |
| `unreadSupportTickets` | `{ type: "unreadSupportTickets", count: N }` | Количество непрочитанных тикетов поддержки |
| `textMessage` | `{ type: "textMessage", text: "..." }` | Текстовое сообщение (alert) |

### 4.3 Обработка aggregateEvent

При получении `aggregateEvent` / `aggregateEventBatch`:
1. Находится Store `AllObjectsService`
2. Ищется запись по `uid`
3. Обновляются поля в Store (Store.fireEvent('datachanged'))
4. Batch разбивается на блоки по 10, каждый блок через `requestAnimationFrame`

---

## 5. Аутентификация

### 5.1 Схема

```
1. POST /billing/j_spring_security_check
   → Form: j_username, j_password, _spring_security_remember_me
   → Set-Cookie: JSESSIONID, remember-me
   → Redirect: /billing/index.html (303)

2. GET /billing/index.html
   → Загружает ExtJS приложение
   → Загружает Ext.Direct API: /billing/EDS/api-debug.js
   
3. Ext.Direct provider инициализируется:
   → Ext.direct.Manager.addProvider(Ext.app.REMOTING_API)
   → Все RPC/Store вызовы через JSESSIONID cookie
   
4. Logout:
   → loginService.logout() (Ext.Direct RPC)
   → Redirect: /billing/login.html
```

### 5.2 Файл прав: billingAdmins.properties

```
# username=password,role1,role2,...
12345=12345,admin
12346=12346,admin
```

### 5.3 Роли и права (из RolesService)

**Роли:** `admin`, `superuser`, `user`, `servicer`

**Права (authorities):**
```
AccountView, AccountCreate, AccountDataSet, AccountDelete
TariffView, TariffPlanCreate, TariffPlanDataSet, TariffPlanDelete
EquipmentView, EquipmentCreate, EquipmentDataSet, EquipmentDelete
ObjectView, ObjectCreate, ObjectDataSet, ObjectDelete
ObjectRestore, ObjectRemove, EquipmentRestore, EquipmentRemove
EquipmentTypesView, EquipmentTypesCreate, EquipmentTypesDataSet, EquipmentTypesDelete
UserView, UserCreate, UserDataSet, UserDelete
ChangeRoles, ChangePermissions, ChangeBalance, DealerBackdoor
```

---

## 6. Сводная таблица: JS → Backend mapping

| JS вызов (из billing/*.js) | Backend класс | Тип |
|----------------------------|---------------|-----|
| `loginService.getLogin()` | LoginService.java | RPC |
| `loginService.logout()` | LoginService.java | RPC |
| `rolesService.checkAdminRole()` | RolesService.scala | RPC |
| `rolesService.getAvailableUserTypes()` | RolesService.scala | RPC |
| `rolesService.checkChangeRoleAuthority()` | RolesService.scala | RPC |
| `rolesService.updateUserRole()` | RolesService.scala | RPC |
| `rolesService.getUserRole()` | RolesService.scala | RPC |
| `rolesService.update()` | RolesService.scala | RPC |
| `accountData.updateData()` | AccountData.java | RPC |
| `accountData.loadData()` | AccountData.java | RPC |
| `accountsStoreService.remove()` | AccountsStoreService.scala | RPC |
| `accountsStoreService.addToAccount()` | AccountsStoreService.scala | RPC |
| `objectData.updateData()` | ObjectData.java | RPC |
| `objectData.loadData()` | ObjectData.java | RPC |
| `objectData.getObjectSleepers()` | ObjectData.java | RPC |
| `allObjectsService.remove()` | AllObjectsService.scala | RPC |
| `allObjectsService.delete()` | AllObjectsService.scala | RPC |
| `equipmentData.updateData()` | EquipmentData.java | RPC |
| `equipmentData.loadData()` | EquipmentData.java | RPC |
| `equipmentTypesData.updateData()` | EquipmentTypesData.java | RPC |
| `equipmentTypesData.loadData()` | EquipmentTypesData.java | RPC |
| `equipmentTypesData.loadMarkByType()` | EquipmentTypesData.java | RPC |
| `equipmentTypesData.loadModelByMark()` | EquipmentTypesData.java | RPC |
| `accountsEquipmentService.modify()` | AccountsEquipmentService.scala | RPC |
| `usersService.create()` | UsersService.scala | RPC |
| `usersService.update()` | UsersService.scala | RPC |
| `usersService.load()` | UsersService.scala | RPC |
| `usersPermissionsService.getPermittedUsersCount()` | UsersPermissionsService.scala | RPC |
| `usersPermissionsService.providePermissions()` | UsersPermissionsService.scala | RPC |
| `dealersService.getDealerParams()` | DealersService.scala | RPC |
| `dealersService.updateDealerParams()` | DealersService.scala | RPC |
| `dealersService.dealerBlocking()` | DealersService.scala | RPC |
| `retranslatorsListService.remove()` | RetranslatorsListService.scala | RPC |
| `retranslatorsService.updateData()` | RetranslatorsService.scala | RPC |
| `terminalMessagesService.remove()` | TerminalMessagesService.scala | RPC |
| `terminalMessagesService.removeInInterval()` | TerminalMessagesService.scala | RPC |
| `terminalMessagesService.reaggregate()` | TerminalMessagesService.scala | RPC |
| `trackerMesService.sendTeltonikaCMD()` | TrackerMesService.scala | RPC |
| `trackerMesService.sendFMB920CMD()` | TrackerMesService.scala | RPC |
| `trackerMesService.sendRuptelaCMD()` | TrackerMesService.scala | RPC |
| `trackerMesService.sendumkaCMD()` | TrackerMesService.scala | RPC |
| `trackerMesService.sendArnaviCMD()` | TrackerMesService.scala | RPC |
| `trackerMesService.ipAndPortToWRC()` | TrackerMesService.scala | RPC |
| `trackerMesService.attachToWRC()` | TrackerMesService.scala | RPC |
| `trackerMesService.sendSMSToTracker()` | TrackerMesService.scala | RPC |
| `configFileLoader.uploadFile()` | ConfigFileLoader.java | FORM_POST |

---

## 7. Статистика

- **Всего @ExtDirectService классов:** ~30
- **Всего @ExtDirectMethod RPC:** ~55 методов
- **Всего Store READ:** ~18 store сервисов
- **Всего Store MODIFY:** ~5 (destroy/create/update)
- **HTTP эндпоинтов:** 7
- **WebSocket событий:** 4 типа
- **MongoDB коллекции:** accounts, objects, equipments, equipmentTypes, users, usersPermissions, billingRoles, billingPermissions, smses, dealers, dealers.balanceHistory, tariffs, balanceHistoryWithDetails, notificationRules

---

> **Документ создан:** 8 февраля 2026  
> **Источник:** legacy-stels (ExtJS 4.2.1 + Spring 4.3.3 + extdirectspring + Scala 2.11)
