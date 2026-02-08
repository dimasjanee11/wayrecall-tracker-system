# 🚀 Runbook: Развёртывание Legacy Stels на macOS

> Проверено: 7–8 февраля 2026, macOS (Apple Silicon)

## Требования

| Компонент | Версия | Комментарий |
|-----------|--------|-------------|
| **Java** | JDK 8 (Zulu/Corretto) | Проект НЕ собирается на Java 11+ |
| **Docker** | 20+ | Для MongoDB и PostgreSQL |
| **Maven** | 3.5+ | Встроен в проект (`./mvnw`) |
| **Git** | любая | Для клонирования |

---

## 1. Клонирование

```bash
# Legacy-стелс лежит рядом с основным проектом (НЕ субмодуль)
cd /path/to/wayrecall-tracker
git clone <legacy-stels-repo-url> legacy-stels
cd legacy-stels
```

## 2. Установка Java 8

```bash
# macOS — проверить установленные JDK:
/usr/libexec/java_home -V

# Если Java 8 нет — установить через Homebrew:
brew install --cask zulu8

# Переключиться на Java 8 (в текущей сессии):
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export PATH=$JAVA_HOME/bin:$PATH

# Проверить:
java -version
# → openjdk version "1.8.0_xxx" (Zulu 8.xx)
```

## 3. Запуск баз данных

```bash
cd legacy-stels
docker compose up -d
```

Поднимаются:
- **MongoDB 3.4** → порт `27017` (контейнер `legacy-stels-mongo-wrc-1`)
- **PostgreSQL 9.6 + PostGIS** → порт `5432` (контейнер `legacy-stels-seniel-pg-1`)

### Проверка:
```bash
docker compose ps
# Оба контейнера должны быть Up

# MongoDB:
docker exec legacy-stels-mongo-wrc-1 mongo --eval "db.version()"
# → 3.4.24

# PostgreSQL:
docker exec -e PGPASSWORD=ttt legacy-stels-seniel-pg-1 \
  psql -h localhost -U nickl -d seniel-pg -c "SELECT version();"
# → PostgreSQL 9.6.22
```

### Credentials (из docker-compose.yml):
| БД | Хост | Порт | User | Password | DB name |
|----|------|------|------|----------|---------|
| MongoDB | localhost | 27017 | — | — | `Seniel-dev2` |
| PostgreSQL | localhost | 5432 | `nickl` | `ttt` | `seniel-pg` |

## 4. Сборка проекта

```bash
cd legacy-stels

# Установить переменные окружения
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD

# Полная сборка (первый раз ~2 мин, скачиваются зависимости):
./mvnw clean install -DskipTests

# Быстрая пересборка (только monitoring, ~30 сек):
./mvnw package -pl monitoring -am -DskipTests -q
```

### Артефакты после сборки:
| Файл | Размер | Назначение |
|------|--------|------------|
| `monitoring/target/dist/monitoring.jar` | ~10 MB | Web-сервер (Jetty) |
| `monitoring/target/dist/libs/` | ~85 MB | Зависимости |
| `monitoring/target/dist/monitoringwebapp/` | — | Мониторинг UI (ExtJS) |
| `monitoring/target/dist/billingwebapp/` | — | Биллинг UI (ExtJS) |
| `packreceiver/target/packreceiver.jar` | ~77 MB | TCP-сервер GPS |

## 5. Запуск Web-сервера (мониторинг + биллинг)

```bash
cd legacy-stels
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD

# Запуск на порту 5193 (в фоне):
java -jar monitoring/target/dist/monitoring.jar 5193 > /tmp/monitoring.log 2>&1 &

# Проверить что запустился (через 5-10 сек):
lsof -i :5193 | grep java
```

### ⚠️ ВАЖНО: Доступ только через 127.0.0.2!

Jetty привязан к виртуальному хосту `127.0.0.2`. Доступ через `localhost` не работает!

| Приложение | URL | Логин | Пароль |
|------------|-----|-------|--------|
| **Мониторинг** | http://127.0.0.2:5193/ | admin | admin |
| **Биллинг** | http://127.0.0.2:5193/billing/ | 12345 | 12345 |

### Остановка:
```bash
pkill -f "monitoring.jar 5193"
```

## 6. Запуск TCP-сервера (packreceiver) — опционально

> Нужен только если подключаете реальные GPS-трекеры

```bash
cd legacy-stels
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD

java -jar packreceiver/target/packreceiver.jar > /tmp/packreceiver.log 2>&1 &
```

Порты для протоколов (из `conf/global.properties`):
| Протокол | Порт |
|----------|------|
| Teltonika | 5001 |
| Wialon | 5002 |
| Ruptela | 5003 |
| NavTelecom | 5004 |

---

## 7. Быстрый старт (всё за 1 минуту)

Если Java 8, Docker установлены и legacy-stels уже склонирован:

```bash
cd legacy-stels

# 1. Базы данных
docker compose up -d

# 2. Сборка + запуск
export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
export WAYRECALL_HOME=$PWD
./mvnw package -pl monitoring -am -DskipTests -q
java -jar monitoring/target/dist/monitoring.jar 5193 &

# 3. Открыть через 10 сек
open http://127.0.0.2:5193/billing/
open http://127.0.0.2:5193/
```

---

## 8. Устранение проблем

### Сборка падает: «source/target 1.8»
→ Проверь `java -version`. Должна быть 1.8.x, не 11/17/21/23.

### `./mvnw: Permission denied`
```bash
chmod +x ./mvnw
```

### Monitoring.jar не запускается / `ClassNotFoundException`
→ Нужна полная сборка `./mvnw clean install -DskipTests` (а не только `package`).

### Браузер: «Не удаётся подключиться» на 127.0.0.2:5193
→ Подождать 10 сек после запуска. Проверить: `lsof -i :5193`.

### MongoDB: «connection refused»
→ `docker compose ps` — контейнер должен быть `Up`. Если нет: `docker compose up -d`.

### Docker: mongo:3.4 image not found
→ MongoDB 3.4 удалена из Docker Hub. Нужно иметь локальный образ или использовать `mongo:4.4` (потребуется проверка совместимости).

---

## Конфигурация

Основные файлы конфигурации:
| Файл | Назначение |
|------|------------|
| `conf/global.properties` | MongoDB, PostgreSQL, SMTP, SMS |
| `conf/packreceiver.properties` | TCP-сервер, Nominatim URL |
| `conf/retranslator.json` | Ретрансляция данных |
| `docker-compose.yml` | Локальные БД (Mongo + PostGIS) |

### Ключевые параметры (conf/global.properties):
```properties
mongoDbHost=localhost
mongoDbPort=27017
mongoDbDatabase=Seniel-dev2

postgresUrl=jdbc:postgresql://localhost:5432/seniel-pg
postgresUser=nickl
postgresPassword=ttt
```
