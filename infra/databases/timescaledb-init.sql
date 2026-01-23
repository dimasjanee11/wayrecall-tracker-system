-- Инициализация TimescaleDB для TrackerGPS
-- Создание таблиц, hypertables, индексов и политик сжатия

-- Включить расширения
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ==============================================
-- GPS POSITIONS (Hypertable)
-- ==============================================

CREATE TABLE IF NOT EXISTS gps_positions (
    time            TIMESTAMPTZ NOT NULL,
    imei            VARCHAR(20) NOT NULL,
    vehicle_id      INTEGER,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    altitude        DOUBLE PRECISION,
    speed           DOUBLE PRECISION,
    heading         DOUBLE PRECISION,
    satellites      INTEGER,
    hdop            DOUBLE PRECISION,
    is_moving       BOOLEAN DEFAULT true,
    is_valid        BOOLEAN DEFAULT true,
    protocol        VARCHAR(20),
    raw_data        TEXT,
    location        GEOGRAPHY(POINT, 4326) -- PostGIS точка
);

-- Создать hypertable с партиционированием по времени (7 дней)
SELECT create_hypertable('gps_positions', 'time', chunk_time_interval => INTERVAL '7 days');

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_gps_imei_time ON gps_positions (imei, time DESC);
CREATE INDEX IF NOT EXISTS idx_gps_vehicle_time ON gps_positions (vehicle_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_gps_location ON gps_positions USING GIST (location);

-- Политика сжатия: сжимать данные старше 7 дней
ALTER TABLE gps_positions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'imei',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('gps_positions', INTERVAL '7 days');

-- Политика удаления: удалять данные старше 1 года
SELECT add_retention_policy('gps_positions', INTERVAL '1 year');

-- ==============================================
-- DEVICES (Обычная таблица)
-- ==============================================

CREATE TABLE IF NOT EXISTS devices (
    id              SERIAL PRIMARY KEY,
    imei            VARCHAR(20) UNIQUE NOT NULL,
    name            VARCHAR(100),
    protocol        VARCHAR(20) NOT NULL,
    vehicle_id      INTEGER,
    is_active       BOOLEAN DEFAULT true,
    last_seen       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_imei ON devices (imei);
CREATE INDEX IF NOT EXISTS idx_devices_vehicle ON devices (vehicle_id);

-- ==============================================
-- VEHICLES (Обычная таблица)
-- ==============================================

CREATE TABLE IF NOT EXISTS vehicles (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    plate_number    VARCHAR(20),
    vehicle_type    VARCHAR(50),
    company_id      INTEGER,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_company ON vehicles (company_id);

-- ==============================================
-- DEVICE COMMANDS (Hypertable)
-- ==============================================

CREATE TABLE IF NOT EXISTS device_commands (
    time            TIMESTAMPTZ NOT NULL,
    command_id      UUID NOT NULL,
    imei            VARCHAR(20) NOT NULL,
    command_type    VARCHAR(50) NOT NULL,
    command_data    JSONB,
    status          VARCHAR(20) DEFAULT 'pending', -- pending, sent, acknowledged, failed
    sent_at         TIMESTAMPTZ,
    ack_at          TIMESTAMPTZ,
    error_message   TEXT
);

-- Создать hypertable
SELECT create_hypertable('device_commands', 'time', chunk_time_interval => INTERVAL '30 days');

-- Индексы
CREATE INDEX IF NOT EXISTS idx_commands_imei_time ON device_commands (imei, time DESC);
CREATE INDEX IF NOT EXISTS idx_commands_status ON device_commands (status);

-- Политика удаления: удалять команды старше 90 дней
SELECT add_retention_policy('device_commands', INTERVAL '90 days');

-- ==============================================
-- GEOZONES (Обычная таблица с PostGIS)
-- ==============================================

CREATE TABLE IF NOT EXISTS geozones (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    zone_type       VARCHAR(50),
    geometry        GEOGRAPHY(POLYGON, 4326) NOT NULL, -- PostGIS полигон
    company_id      INTEGER,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geozones_geometry ON geozones USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_geozones_company ON geozones (company_id);

-- ==============================================
-- GEOZONE EVENTS (Hypertable)
-- ==============================================

CREATE TABLE IF NOT EXISTS geozone_events (
    time            TIMESTAMPTZ NOT NULL,
    event_id        UUID NOT NULL,
    vehicle_id      INTEGER NOT NULL,
    geozone_id      INTEGER NOT NULL,
    event_type      VARCHAR(20) NOT NULL, -- enter, exit
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL
);

-- Создать hypertable
SELECT create_hypertable('geozone_events', 'time', chunk_time_interval => INTERVAL '30 days');

-- Индексы
CREATE INDEX IF NOT EXISTS idx_geozone_events_vehicle ON geozone_events (vehicle_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_geozone_events_zone ON geozone_events (geozone_id, time DESC);

-- Политика удаления: удалять события старше 6 месяцев
SELECT add_retention_policy('geozone_events', INTERVAL '6 months');

-- ==============================================
-- CONTINUOUS AGGREGATES (Материализованные представления)
-- ==============================================

-- Агрегация: суточная статистика по устройствам
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_device_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS day,
    imei,
    vehicle_id,
    COUNT(*) as position_count,
    AVG(speed) as avg_speed,
    MAX(speed) as max_speed,
    SUM(CASE WHEN is_moving THEN 1 ELSE 0 END) as moving_count
FROM gps_positions
GROUP BY day, imei, vehicle_id;

-- Политика обновления continuous aggregate каждый час
SELECT add_continuous_aggregate_policy('daily_device_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- ==============================================
-- ФУНКЦИИ
-- ==============================================

-- Функция: получить последнюю позицию устройства
CREATE OR REPLACE FUNCTION get_last_position(device_imei VARCHAR)
RETURNS TABLE (
    time TIMESTAMPTZ,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT gp.time, gp.latitude, gp.longitude, gp.speed, gp.heading
    FROM gps_positions gp
    WHERE gp.imei = device_imei
    ORDER BY gp.time DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Функция: проверить точку в геозоне
CREATE OR REPLACE FUNCTION check_point_in_geozone(
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION
)
RETURNS TABLE (
    geozone_id INTEGER,
    geozone_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT gz.id, gz.name
    FROM geozones gz
    WHERE gz.is_active = true
      AND ST_Contains(gz.geometry::geometry, ST_SetSRID(ST_MakePoint(lon, lat), 4326))
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- ВСТАВИТЬ ТЕСТОВЫЕ ДАННЫЕ (опционально)
-- ==============================================

-- Тестовое устройство
INSERT INTO devices (imei, name, protocol, is_active)
VALUES ('123456789012345', 'Test Device 1', 'gt06', true)
ON CONFLICT (imei) DO NOTHING;

-- Тестовое транспортное средство
INSERT INTO vehicles (name, plate_number, vehicle_type)
VALUES ('Test Vehicle', 'A123BC', 'truck')
ON CONFLICT DO NOTHING;

COMMENT ON TABLE gps_positions IS 'GPS позиции устройств (TimescaleDB Hypertable)';
COMMENT ON TABLE devices IS 'Зарегистрированные GPS устройства';
COMMENT ON TABLE vehicles IS 'Транспортные средства';
COMMENT ON TABLE device_commands IS 'Команды отправленные на устройства';
COMMENT ON TABLE geozones IS 'Геозоны (полигоны на карте)';
COMMENT ON TABLE geozone_events IS 'События въезда/выезда из геозон';
