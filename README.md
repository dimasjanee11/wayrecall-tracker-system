# Wayrecall Tracker System

GPS мониторинг система для отслеживания транспорта в реальном времени.

**Стек:** Scala 3 + ZIO 2 + Kafka + Redis + TimescaleDB

---

## 🏗️ Архитектура

Микросервисная система из 6 компонентов:

### Block 1: GPS Collection & Data Flow
- **Connection Manager** - приём GPS данных по TCP (4 протокола: Teltonika, Wialon, Ruptela, NavTelecom)
- **History Writer** - сохранение истории в TimescaleDB

### Block 2: Business Logic
- **Device Manager** - управление трекерами и командами
- **Geozone Service** - геофенсинг (проверка геозон)
- **Notification Service** - уведомления (Email, SMS, Push, Telegram)
- **Analytics Service** - отчёты и статистика

### Block 3: API & Frontend
- **API Gateway** - REST API (HTTP)
- **WebSocket Service** - realtime обновления
- **React Frontend** - веб-интерфейс

---

## 🚀 Быстрый старт

### Требования
- Docker & Docker Compose
- JDK 11+
- SBT 1.9+
- Git

### Локальная разработка

```bash
# 1. Клонировать с submodules
git clone --recursive https://github.com/YOUR_USERNAME/wayrecall-tracker-system.git
cd wayrecall-tracker-system

# 2. Запустить инфраструктуру
docker-compose up -d

# 3. Компилировать все сервисы
sbt compile

# 4. Запустить Connection Manager
sbt "project connection-manager" run

# 5. Запустить History Writer
sbt "project history-writer" run
```

### Тесты

```bash
# Все тесты
sbt test

# Конкретный сервис
sbt "project connection-manager" test
```

---

## 📁 Структура проекта

```
wayrecall-tracker-system/
├── docs/                    # Документация
├── services/                # Микросервисы (submodules)
│   ├── connection-manager/
│   ├── history-writer/
│   ├── device-manager/
│   ├── geozone-service/
│   ├── notification-service/
│   └── api-gateway/
├── learning/                # Примеры (Kafka, Redis)
├── docker-compose.yml       # Инфраструктура
└── build.sbt               # Root SBT конфиг
```

---

## 📊 Данные

### Входные потоки
- **TCP (port 5001-5004):** GPS точки от трекеров
- **REST API (port 8080):** Команды от пользователя

### Хранилища
- **Redis:** Position cache, command queue, configuration
- **TimescaleDB:** GPS история (3+ года)
- **PostgreSQL:** Пользователи, геозоны, отчёты

### Выходные потоки
- **WebSocket (port 8081):** Realtime позиции на карте
- **Kafka topics:** Events для других сервисов
- **Email/SMS/Push:** Уведомления

---

## 🔧 Конфигурация

### Environment variables

```bash
# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Kafka
KAFKA_BOOTSTRAP_SERVERS=localhost:9092

# TimescaleDB
DB_HOST=localhost
DB_PORT=5432
DB_NAME=tracker
DB_USER=tracker
DB_PASSWORD=tracker123

# Connection Manager
CM_PORT_TELTONIKA=5001
CM_PORT_WIALON=5002
CM_PORT_RUPTELA=5003
CM_PORT_NAVTELECOM=5004
CM_HTTP_PORT=8080
```

---

## 📚 Документация

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - общая архитектура
- [CONNECTION_MANAGER_ANALYSIS.md](docs/CONNECTION_MANAGER_ANALYSIS.md) - анализ Connection Manager
- [CONNECTION_MANAGER_PLAN.md](docs/CONNECTION_MANAGER_PLAN.md) - план улучшений
- [DEPLOYMENT.md](docs/DEPLOYMENT.md) - развёртывание в production
- [API.md](docs/API.md) - REST API справочник
- [MONITORING.md](docs/MONITORING.md) - мониторинг и алерты

---

## 🤝 Contributing

1. Fork репо
2. Создать branch (`git checkout -b feature/your-feature`)
3. Commit (`git commit -am 'Add feature'`)
4. Push (`git push origin feature/your-feature`)
5. Открыть Pull Request

---

## 📝 Лицензия

MIT

---

## 📞 Контакты

Вопросы? Открыть Issue на GitHub.

