# 🚀 Развертывание Legacy Stels локально на Mac

**Дата:** 7 февраля 2026  
**Система:** macOS  
**Проект:** WayRecall Legacy (Java/Scala + Spring + MongoDB + PostgreSQL)

---

## 📋 Предварительная диагностика

### ✅ Проверка окружения

**Java:**
```
openjdk version "23.0.2" 2025-01-21
OpenJDK Runtime Environment Corretto-23.0.2.7.1
```
❗ **Проблема:** Проект требует Java 8, а установлена Java 23

**Maven:**
```
Apache Maven 3.9.11
```
✅ **ОК** (проект использует Maven 3.5.4+)

---

## 🏗️ Архитектура Legacy проекта

**Технологический стек:**
- **Язык:** Scala 2.11.6 + Java 8
- **Фреймворк:** Spring Framework 4.3.3 + Spring Security 4.1.3
- **БД:** MongoDB 3.4 + PostgreSQL 9.6 с PostGIS
- **Сборка:** Maven (multi-module проект)
- **Web-сервер:** Jetty 9.2.29
- **TCP-сервер:** Netty 4.0.23

**Модули проекта:**
```
wayrecall/
├── core/                   # Общая бизнес-логика
├── monitoring/             # Web UI + REST API (Jetty)
├── packreceiver/           # TCP server для приема GPS пакетов (Netty)
├── tools/                  # Утилиты
├── modules/
│   ├── odsmosru/          # Интеграция с ОДСМ
│   └── m2msms/            # SMS интеграция
├── integrationtests/       # Интеграционные тесты
└── testutils/             # Тестовые утилиты
```

**Два процесса в production:**
1. **packreceiver** — TCP сервер для приёма GPS пакетов от трекеров
2. **monitoring** — Web-интерфейс + REST API (порт 9080)

---

## 🎯 План развертывания

### Шаг 1: Установка Java 8 (JDK 8)
### Шаг 2: Поднятие баз данных через Docker
### Шаг 3: Настройка переменных окружения
### Шаг 4: Сборка проекта через Maven
### Шаг 5: Инициализация PostgreSQL схемы
### Шаг 6: Запуск web-сервера (monitoring)
### Шаг 7: Запуск TCP-сервера (packreceiver)
### Шаг 8: Проверка работоспособности

---

## 📝 Лог выполнения

### 🔧 Шаг 1: Установка Java 8

**Проблема:** Проект собирается под Java 8 (`javac.version=1.8`), но установлена Java 23.

**Проверка установленных Java:**
```bash
/usr/libexec/java_home -V
```

**Результат:**
```
✅ Java 23 (Corretto)
✅ Java 21 (OpenJDK)  
✅ Java 8 (Zulu 8.88.0.19) — ЭТО НАМ НУЖНО!
```

**Java 8 уже установлена!** Путь: `/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home`

**Переключение на Java 8 для текущей сессии:**
```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export PATH=$JAVA_HOME/bin:$PATH
java -version
```

**Проверка:**
```
openjdk version "1.8.0_462"
OpenJDK Runtime Environment (Zulu 8.88.0.19-CA-macos-aarch64)
```

✅ **Java 8 активна!**

---

### 🐳 Шаг 2: Поднятие баз данных через Docker

**Базы данных из legacy-stels/docker-compose.yml:**
1. **mongo:3.4** — основное хранилище (порт 27017) ✅ образ есть
2. **kartoza/postgis:9.6-2.4** — PostgreSQL 9.6 + PostGIS для геозон (порт 5432) ⏳ скачивается

**Важно:** Используем ТОЛЬКО старый docker-compose из legacy-stels!

**Команда запуска:**
```bash
cd /Users/wogul/vsCodeProjects/wayrecall-tracker/legacy-stels
docker compose up -d
```

**Проверка:**
```bash
docker compose ps
```

**Результат:**
```
NAME                       IMAGE                     STATUS              PORTS
legacy-stels-mongo-wrc-1   mongo:3.4                 Up About a minute   27016-27017:27017
legacy-stels-seniel-pg-1   kartoza/postgis:9.6-2.4   Up About a minute   5432:5432
```

✅ **Базы данных запущены!**

**Проверка работоспособности:**

MongoDB:
```bash
docker exec legacy-stels-mongo-wrc-1 mongo --eval "db.version()"
# Результат: MongoDB shell version v3.4.24 ✅
```

PostgreSQL:
```bash
docker exec -e PGPASSWORD=ttt legacy-stels-seniel-pg-1 psql -h localhost -U nickl -d seniel-pg -c "SELECT version();"
# Результат: PostgreSQL 9.6.22 ✅
```

**Credentials (из docker-compose.yml):**
- DB: `seniel-pg`
- User: `nickl` (старый разработчик)
- Pass: `ttt`

---

### ⚙️ Шаг 3: Настройка переменных окружения и конфигов

**Проверка конфигурации:**
```bash
cat conf/global.properties | head -20
```

Конфиг уже настроен на локальные базы:
- MongoDB: `localhost:27017`, database: `Seniel-dev2`
- PostgreSQL: `localhost:5432`, database: `seniel-pg`, user: `nickl`, pass: `ttt`

**Установка переменной окружения:**
```bash
export WAYRECALL_HOME=/Users/wogul/vsCodeProjects/wayrecall-tracker/legacy-stels
```

**ThirdPartyJS:**
- ❌ **maven.uits-labs.ru недоступен** (старый внутренний репозиторий)
- ✅ **ExtJS 4.2.1 и OpenLayers частично есть в проекте** (только локализации и стили)
- ⚠️ **Нужно скачать основные JS файлы** из публичных источников

**План:**
1. Скачать ExtJS 4.2.1 из архива Sencha
2. Скачать OpenLayers 2.13.1 из архива
3. Положить в `monitoring/src/main/webapp-monitoring/`

---

### 🔨 Шаг 4: Скачивание ThirdPartyJS библиотек

**ExtJS 4.2.1:**

✅ Скачаны основные файлы:
- `ext-all-debug.js` (3.2 MB) — полная debug версия
- `ext-all.js` (1.4 MB) — production версия

⚠️ CSS файлы проблематичны — старые версии ExtJS удалены из CDN.

**OpenLayers 2.13.1:**

✅ Скачан:
- `OpenLayers.js` (752 KB) — полная библиотека

**Статус:** Основные JS файлы есть. Попробуем собрать проект!

---

### 🔨 Шаг 5: Сборка проекта через Maven

**Команда сборки:**
```bash
cd /Users/wogul/vsCodeProjects/wayrecall-tracker/legacy-stels
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD
./mvnw clean install -DskipTests
```

**Результат:**
```
[INFO] BUILD SUCCESS
[INFO] Total time: 01:33 min
```

**Собранные артефакты:**

1. **packreceiver.jar** (77 MB) — TCP-сервер для приёма GPS пакетов
   - Путь: `packreceiver/target/packreceiver.jar`

2. **monitoring.jar** (10 MB) — Web-сервер (Jetty + REST API + UI)
   - Путь: `monitoring/target/dist/monitoring.jar`
   - Web-приложения: `monitoringwebapp/`, `billingwebapp/`, `workflowapp/`

✅ **Проект собран успешно!**

---

### 🚀 Шаг 6: Запуск Web-сервера (monitoring)

**Команда запуска в фоновом режиме:**
```bash
cd /Users/wogul/vsCodeProjects/wayrecall-tracker/legacy-stels
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD
nohup java -jar monitoring/target/dist/monitoring.jar 5193 > logs/monitoring-server.log 2>&1 &
```

**Результат:**
- ✅ Сервер запущен (PID покажется в терминале, например `[1] 26080`)
- ✅ Логи пишутся в `logs/monitoring-server.log`
- ✅ 3 web-приложения развёрнуты на виртуальном хосте **127.0.0.2:5193**

**⚠️ ВАЖНО! Доступ только через 127.0.0.2 (не localhost):**
- **Биллинг**: http://127.0.0.2:5193/billing/
- **Мониторинг**: http://127.0.0.2:5193/

**Причина:** Jetty привязан к виртуальному хосту 127.0.0.2 (видно в логах: `AVAILABLE,127.0.0.2`)

**Просмотр логов:**
```bash
tail -f logs/monitoring-server.log
```

**Остановка сервера:**
```bash
# Найти PID процесса Java
lsof -i :5193 | grep java
# Остановить (замените <PID> на реальный номер)
kill <PID>
```

**Запускаем:**

