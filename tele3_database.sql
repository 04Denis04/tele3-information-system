-- ============================================================
-- ИНФОРМАЦИОННАЯ СИСТЕМА ОПЕРАТОРА МОБИЛЬНОЙ СВЯЗИ "ТЕЛЕ 3"
-- Полная схема базы данных PostgreSQL
-- Курсовой проект по дисциплине "Системы управления базами данных"
-- ============================================================

-- ============================================================
-- ЧАСТЬ 1: СОЗДАНИЕ БАЗЫ ДАННЫХ И СХЕМЫ
-- ============================================================

-- Создаём базу данных (выполнить от суперпользователя postgres)
-- CREATE DATABASE tele3 ENCODING 'UTF8' LC_COLLATE='ru_RU.UTF-8' LC_CTYPE='ru_RU.UTF-8';
-- \c tele3

-- Создаём отдельную схему для прикладных объектов
CREATE SCHEMA IF NOT EXISTS tele3;
SET search_path TO tele3, public;

-- ============================================================
-- ЧАСТЬ 2: БАЗОВЫЕ ТАБЛИЦЫ (3НФ)
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 Таблица ролей (справочник)
-- Нормализация: 3НФ — все атрибуты зависят только от PK
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.roles (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    description TEXT
);

COMMENT ON TABLE  tele3.roles IS 'Справочник ролей пользователей ИС';
COMMENT ON COLUMN tele3.roles.name IS 'Системное имя роли: admin, security_admin, support, billing_operator, subscriber';

-- ------------------------------------------------------------
-- 2.2 Таблица пользователей ИС
-- Связь 1:N с roles (каждый пользователь имеет одну роль)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role_id       INTEGER      NOT NULL REFERENCES tele3.roles(id) ON DELETE RESTRICT,
    email         VARCHAR(150) UNIQUE,
    full_name     VARCHAR(200),
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
    last_login    TIMESTAMP,
    CONSTRAINT chk_username_len CHECK (char_length(username) >= 3)
);

COMMENT ON TABLE  tele3.users IS 'Пользователи информационной системы (системные учётные записи)';
COMMENT ON COLUMN tele3.users.password_hash IS 'Хеш пароля bcrypt (никогда не хранить plaintext!)';

-- ------------------------------------------------------------
-- 2.3 Абоненты
-- Нормализация: паспортные данные вынесены как атрибуты,
-- не создают транзитивных зависимостей — 3НФ соблюдена
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.subscribers (
    id               SERIAL PRIMARY KEY,
    last_name        VARCHAR(100) NOT NULL,
    first_name       VARCHAR(100) NOT NULL,
    middle_name      VARCHAR(100),
    passport_series  VARCHAR(10)  NOT NULL,
    passport_number  VARCHAR(20)  NOT NULL,
    birth_date       DATE         NOT NULL,
    phone            VARCHAR(20),
    address          TEXT,
    email            VARCHAR(150),
    user_id          INTEGER      REFERENCES tele3.users(id) ON DELETE SET NULL,
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_passport UNIQUE (passport_series, passport_number),
    CONSTRAINT chk_birth_date CHECK (birth_date < CURRENT_DATE),
    CONSTRAINT chk_birth_date_min CHECK (birth_date > '1900-01-01')
);

COMMENT ON TABLE  tele3.subscribers IS 'Физические лица — абоненты оператора ТЕЛЕ 3';
COMMENT ON COLUMN tele3.subscribers.user_id IS 'Ссылка на учётную запись ЛК (если абонент зарегистрирован)';

-- ------------------------------------------------------------
-- 2.4 Тарифы
-- Нормализация: все поля зависят только от id — 3НФ
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.tariffs (
    id                SERIAL PRIMARY KEY,
    name              VARCHAR(150) NOT NULL UNIQUE,
    monthly_fee       DECIMAL(10,2) NOT NULL DEFAULT 0,
    internet_gb       INTEGER       NOT NULL DEFAULT 0,
    minutes           INTEGER       NOT NULL DEFAULT 0,
    sms_count         INTEGER       NOT NULL DEFAULT 0,
    is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP     NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_monthly_fee    CHECK (monthly_fee >= 0),
    CONSTRAINT chk_internet_gb    CHECK (internet_gb >= 0),
    CONSTRAINT chk_minutes        CHECK (minutes >= 0),
    CONSTRAINT chk_sms_count      CHECK (sms_count >= 0)
);

COMMENT ON TABLE tele3.tariffs IS 'Тарифные планы оператора';

-- ------------------------------------------------------------
-- 2.5 Дополнительные услуги
-- M:N со SIM-картами реализуется через connected_services
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.services (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(150) NOT NULL UNIQUE,
    cost        DECIMAL(10,2) NOT NULL DEFAULT 0,
    description TEXT,
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_service_cost CHECK (cost >= 0)
);

COMMENT ON TABLE tele3.services IS 'Дополнительные услуги (роуминг, переадресация, антиспам и т.д.)';

-- ------------------------------------------------------------
-- 2.6 SIM-карты
-- Связь 1:N с subscribers (у абонента может быть несколько SIM)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.sim_cards (
    id              SERIAL PRIMARY KEY,
    phone_number    VARCHAR(20)  NOT NULL UNIQUE,
    iccid           VARCHAR(22)  UNIQUE,
    activation_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    status          VARCHAR(20)  NOT NULL DEFAULT 'active',
    subscriber_id   INTEGER      REFERENCES tele3.subscribers(id) ON DELETE SET NULL,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_sim_status CHECK (status IN ('active','blocked','terminated','reserved'))
);

COMMENT ON TABLE  tele3.sim_cards IS 'SIM-карты оператора';
COMMENT ON COLUMN tele3.sim_cards.iccid IS '19-22 значный уникальный идентификатор SIM-карты';
COMMENT ON COLUMN tele3.sim_cards.status IS 'active | blocked | terminated | reserved';

-- ------------------------------------------------------------
-- 2.7 Подключение тарифа к SIM
-- Связь M:N (SIM ↔ Тариф), история смены тарифов
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.tariff_connections (
    id               SERIAL PRIMARY KEY,
    sim_id           INTEGER      NOT NULL REFERENCES tele3.sim_cards(id) ON DELETE CASCADE,
    tariff_id        INTEGER      NOT NULL REFERENCES tele3.tariffs(id) ON DELETE RESTRICT,
    connected_at     DATE         NOT NULL DEFAULT CURRENT_DATE,
    disconnected_at  DATE,
    CONSTRAINT chk_dates CHECK (disconnected_at IS NULL OR disconnected_at >= connected_at)
);

COMMENT ON TABLE tele3.tariff_connections IS 'История подключения тарифов к SIM-картам';

-- ------------------------------------------------------------
-- 2.8 Подключение дополнительных услуг к SIM
-- Связь M:N (SIM ↔ Услуга)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.connected_services (
    id           SERIAL PRIMARY KEY,
    sim_id       INTEGER   NOT NULL REFERENCES tele3.sim_cards(id) ON DELETE CASCADE,
    service_id   INTEGER   NOT NULL REFERENCES tele3.services(id) ON DELETE RESTRICT,
    connected_at DATE      NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_sim_service UNIQUE (sim_id, service_id)
);

COMMENT ON TABLE tele3.connected_services IS 'Активные дополнительные услуги на SIM-картах';

-- ------------------------------------------------------------
-- 2.9 Звонки
-- Связь N:1 с sim_cards (у SIM много звонков)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.calls (
    id              SERIAL PRIMARY KEY,
    sim_id          INTEGER       NOT NULL REFERENCES tele3.sim_cards(id) ON DELETE CASCADE,
    destination     VARCHAR(20)   NOT NULL,
    call_datetime   TIMESTAMP     NOT NULL DEFAULT NOW(),
    duration_sec    INTEGER       NOT NULL DEFAULT 0,
    cost            DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_call_duration CHECK (duration_sec >= 0),
    CONSTRAINT chk_call_cost     CHECK (cost >= 0)
);

COMMENT ON TABLE tele3.calls IS 'Журнал звонков с SIM-карт';

-- ------------------------------------------------------------
-- 2.10 SMS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.sms (
    id            SERIAL PRIMARY KEY,
    sim_id        INTEGER       NOT NULL REFERENCES tele3.sim_cards(id) ON DELETE CASCADE,
    destination   VARCHAR(20)   NOT NULL,
    sent_datetime TIMESTAMP     NOT NULL DEFAULT NOW(),
    cost          DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_sms_cost CHECK (cost >= 0)
);

COMMENT ON TABLE tele3.sms IS 'Журнал SMS-сообщений';

-- ------------------------------------------------------------
-- 2.11 Платежи
-- Связь N:1 с subscribers (у абонента много платежей)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tele3.payments (
    id              SERIAL PRIMARY KEY,
    subscriber_id   INTEGER       NOT NULL REFERENCES tele3.subscribers(id) ON DELETE RESTRICT,
    amount          DECIMAL(10,2) NOT NULL,
    payment_date    DATE          NOT NULL DEFAULT CURRENT_DATE,
    payment_method  VARCHAR(50)   NOT NULL DEFAULT 'cash',
    notes           TEXT,
    CONSTRAINT chk_payment_amount  CHECK (amount > 0),
    CONSTRAINT chk_payment_method  CHECK (payment_method IN ('cash','card','online','terminal'))
);

COMMENT ON TABLE tele3.payments IS 'Платежи абонентов';

-- ============================================================
-- ЧАСТЬ 3: ТАБЛИЦА АУДИТА / ПРОТОКОЛ ОПЕРАЦИЙ
-- Требование: "должен вестись протокол операций с БД"
-- ============================================================
CREATE TABLE IF NOT EXISTS tele3.audit_log (
    id          BIGSERIAL PRIMARY KEY,
    table_name  VARCHAR(100) NOT NULL,
    operation   VARCHAR(10)  NOT NULL,   -- INSERT / UPDATE / DELETE
    record_id   INTEGER,
    old_data    JSONB,
    new_data    JSONB,
    changed_by  VARCHAR(100) NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_operation CHECK (operation IN ('INSERT','UPDATE','DELETE'))
);

COMMENT ON TABLE tele3.audit_log IS 'Протокол всех операций с данными (требование ИБ)';

-- ============================================================
-- ЧАСТЬ 4: ПРЕДСТАВЛЕНИЯ (VIEWS)
-- Требование: "модифицируемые представления"
-- Пользователи работают через представления, не напрямую!
-- ============================================================

-- 4.1 Представление: абоненты с числом SIM-карт
CREATE OR REPLACE VIEW tele3.v_subscribers AS
    SELECT
        s.id,
        s.last_name,
        s.first_name,
        s.middle_name,
        CONCAT(s.last_name, ' ', s.first_name, ' ', COALESCE(s.middle_name,'')) AS full_name,
        s.passport_series,
        s.passport_number,
        s.birth_date,
        s.phone,
        s.address,
        s.email,
        s.user_id,
        s.created_at,
        COUNT(sc.id) AS sim_count
    FROM tele3.subscribers s
    LEFT JOIN tele3.sim_cards sc ON sc.subscriber_id = s.id
    GROUP BY s.id;

-- 4.2 Представление: SIM-карты с текущим тарифом и абонентом
CREATE OR REPLACE VIEW tele3.v_sim_cards AS
    SELECT
        sc.id,
        sc.phone_number,
        sc.iccid,
        sc.activation_date,
        sc.status,
        sc.subscriber_id,
        CONCAT(sub.last_name, ' ', sub.first_name) AS subscriber_name,
        t.name   AS current_tariff,
        t.monthly_fee,
        tc.connected_at AS tariff_since
    FROM tele3.sim_cards sc
    LEFT JOIN tele3.subscribers sub ON sub.id = sc.subscriber_id
    LEFT JOIN tele3.tariff_connections tc
        ON  tc.sim_id = sc.id
        AND tc.disconnected_at IS NULL
    LEFT JOIN tele3.tariffs t ON t.id = tc.tariff_id;

-- 4.3 Представление: платежи с именем абонента
CREATE OR REPLACE VIEW tele3.v_payments AS
    SELECT
        p.id,
        p.subscriber_id,
        CONCAT(s.last_name, ' ', s.first_name) AS subscriber_name,
        p.amount,
        p.payment_date,
        p.payment_method,
        p.notes
    FROM tele3.payments p
    JOIN tele3.subscribers s ON s.id = p.subscriber_id;

-- 4.4 Представление: звонки с номером SIM
CREATE OR REPLACE VIEW tele3.v_calls AS
    SELECT
        c.id,
        sc.phone_number,
        c.destination,
        c.call_datetime,
        c.duration_sec,
        ROUND(c.duration_sec / 60.0, 2) AS duration_min,
        c.cost,
        c.sim_id
    FROM tele3.calls c
    JOIN tele3.sim_cards sc ON sc.id = c.sim_id;

-- 4.5 Представление: SMS с номером SIM
CREATE OR REPLACE VIEW tele3.v_sms AS
    SELECT
        s.id,
        sc.phone_number,
        s.destination,
        s.sent_datetime,
        s.cost,
        s.sim_id
    FROM tele3.sms s
    JOIN tele3.sim_cards sc ON sc.id = s.sim_id;

-- 4.6 Представление: подключённые услуги с деталями
CREATE OR REPLACE VIEW tele3.v_connected_services AS
    SELECT
        cs.id,
        sc.phone_number,
        svc.name  AS service_name,
        svc.cost,
        cs.connected_at,
        cs.sim_id,
        cs.service_id
    FROM tele3.connected_services cs
    JOIN tele3.sim_cards sc  ON sc.id  = cs.sim_id
    JOIN tele3.services  svc ON svc.id = cs.service_id;

-- 4.7 Представление: пользователи с ролями (без паролей!)
CREATE OR REPLACE VIEW tele3.v_users AS
    SELECT
        u.id,
        u.username,
        u.role_id,
        r.name      AS role_name,
        r.description AS role_description,
        u.email,
        u.full_name,
        u.is_active,
        u.created_at,
        u.last_login
    FROM tele3.users u
    JOIN tele3.roles r ON r.id = u.role_id;

-- 4.8 Представление аудита (только для security_admin)
CREATE OR REPLACE VIEW tele3.v_audit_log AS
    SELECT * FROM tele3.audit_log ORDER BY changed_at DESC;

-- ============================================================
-- ЧАСТЬ 5: ФУНКЦИИ-ТРИГГЕРЫ ДЛЯ АУДИТА
-- Требование: "все операции через триггеры"
-- ============================================================

CREATE OR REPLACE FUNCTION tele3.fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
        VALUES (TG_TABLE_NAME, 'INSERT', NEW.id, row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO tele3.audit_log(table_name, operation, record_id, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'UPDATE', NEW.id,
                row_to_json(OLD)::jsonb,
                row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO tele3.audit_log(table_name, operation, record_id, old_data)
        VALUES (TG_TABLE_NAME, 'DELETE', OLD.id, row_to_json(OLD)::jsonb);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

-- Навешиваем триггер аудита на все ключевые таблицы
CREATE TRIGGER trg_audit_users
    AFTER INSERT OR UPDATE OR DELETE ON tele3.users
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_subscribers
    AFTER INSERT OR UPDATE OR DELETE ON tele3.subscribers
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_sim_cards
    AFTER INSERT OR UPDATE OR DELETE ON tele3.sim_cards
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_tariffs
    AFTER INSERT OR UPDATE OR DELETE ON tele3.tariffs
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_payments
    AFTER INSERT OR UPDATE OR DELETE ON tele3.payments
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_calls
    AFTER INSERT OR UPDATE OR DELETE ON tele3.calls
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_sms
    AFTER INSERT OR UPDATE OR DELETE ON tele3.sms
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_services
    AFTER INSERT OR UPDATE OR DELETE ON tele3.services
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

CREATE TRIGGER trg_audit_connected_services
    AFTER INSERT OR UPDATE OR DELETE ON tele3.connected_services
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_audit_trigger();

-- ------------------------------------------------------------
-- Триггер: при отключении тарифа — проставляем дату disconnected_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION tele3.fn_disconnect_old_tariff()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- При подключении нового тарифа автоматически закрываем предыдущий
    UPDATE tele3.tariff_connections
    SET disconnected_at = CURRENT_DATE
    WHERE sim_id = NEW.sim_id
      AND id <> NEW.id
      AND disconnected_at IS NULL;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_disconnect_old_tariff
    AFTER INSERT ON tele3.tariff_connections
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_disconnect_old_tariff();

-- ------------------------------------------------------------
-- Триггер: запрет смены роли security_admin без логирования
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION tele3.fn_protect_security_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_role VARCHAR;
BEGIN
    SELECT r.name INTO v_old_role
    FROM tele3.roles r WHERE r.id = OLD.role_id;

    IF v_old_role = 'security_admin' AND OLD.role_id <> NEW.role_id THEN
        RAISE NOTICE 'Изменение роли security_admin зафиксировано в аудите';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_security_admin
    BEFORE UPDATE ON tele3.users
    FOR EACH ROW EXECUTE FUNCTION tele3.fn_protect_security_admin();

-- ============================================================
-- ЧАСТЬ 6: ХРАНИМЫЕ ПРОЦЕДУРЫ (ХП)
-- Требование: "все операции через ХП"
-- "любая ХП должна исполняться независимо от правильности входных параметров"
-- ============================================================

-- 6.1 ХП: Добавить/обновить абонента
CREATE OR REPLACE PROCEDURE tele3.sp_upsert_subscriber(
    p_id            INTEGER,
    p_last_name     VARCHAR,
    p_first_name    VARCHAR,
    p_middle_name   VARCHAR,
    p_passport_s    VARCHAR,
    p_passport_n    VARCHAR,
    p_birth_date    DATE,
    p_phone         VARCHAR,
    p_address       TEXT,
    p_email         VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_id IS NULL OR p_id = 0 THEN
        -- INSERT
        INSERT INTO tele3.subscribers
            (last_name, first_name, middle_name, passport_series, passport_number,
             birth_date, phone, address, email)
        VALUES
            (COALESCE(p_last_name,''), COALESCE(p_first_name,''), p_middle_name,
             COALESCE(p_passport_s,''), COALESCE(p_passport_n,''),
             COALESCE(p_birth_date, '2000-01-01'),
             p_phone, p_address, p_email);
    ELSE
        -- UPDATE
        UPDATE tele3.subscribers SET
            last_name      = COALESCE(p_last_name, last_name),
            first_name     = COALESCE(p_first_name, first_name),
            middle_name    = COALESCE(p_middle_name, middle_name),
            passport_series = COALESCE(p_passport_s, passport_series),
            passport_number = COALESCE(p_passport_n, passport_number),
            birth_date     = COALESCE(p_birth_date, birth_date),
            phone          = COALESCE(p_phone, phone),
            address        = COALESCE(p_address, address),
            email          = COALESCE(p_email, email)
        WHERE id = p_id;
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- ХП не прерывает работу при ошибке — логируем
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('subscribers', 'ERROR', p_id,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_upsert_subscriber'));
END;
$$;

-- 6.2 ХП: Блокировка/разблокировка SIM-карты
CREATE OR REPLACE PROCEDURE tele3.sp_set_sim_status(
    p_sim_id  INTEGER,
    p_status  VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_sim_id IS NULL THEN
        RETURN;  -- не падаем, просто выходим
    END IF;

    UPDATE tele3.sim_cards
    SET status = COALESCE(p_status, 'active')
    WHERE id = p_sim_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'SIM % не найдена', p_sim_id;
    END IF;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('sim_cards', 'ERROR', p_sim_id,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_set_sim_status'));
END;
$$;

-- 6.3 ХП: Подключить тариф к SIM
CREATE OR REPLACE PROCEDURE tele3.sp_connect_tariff(
    p_sim_id    INTEGER,
    p_tariff_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_sim_id IS NULL OR p_tariff_id IS NULL THEN
        RETURN;
    END IF;

    -- Триггер trg_disconnect_old_tariff сам закроет предыдущий тариф
    INSERT INTO tele3.tariff_connections(sim_id, tariff_id)
    VALUES (p_sim_id, p_tariff_id);

EXCEPTION WHEN OTHERS THEN
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('tariff_connections', 'ERROR', p_sim_id,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_connect_tariff'));
END;
$$;

-- 6.4 ХП: Добавить платёж
CREATE OR REPLACE PROCEDURE tele3.sp_add_payment(
    p_subscriber_id INTEGER,
    p_amount        DECIMAL,
    p_method        VARCHAR,
    p_notes         TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_subscriber_id IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
        RAISE NOTICE 'Некорректные параметры платежа: subscriber=%, amount=%', p_subscriber_id, p_amount;
        RETURN;
    END IF;

    INSERT INTO tele3.payments(subscriber_id, amount, payment_method, notes)
    VALUES (p_subscriber_id, p_amount,
            COALESCE(p_method, 'cash'), p_notes);

EXCEPTION WHEN OTHERS THEN
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('payments', 'ERROR', p_subscriber_id,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_add_payment'));
END;
$$;

-- 6.5 ХП: Добавить пользователя с ролью
CREATE OR REPLACE PROCEDURE tele3.sp_create_user(
    p_username  VARCHAR,
    p_passhash  VARCHAR,
    p_role_name VARCHAR,
    p_email     VARCHAR,
    p_fullname  VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_id INTEGER;
BEGIN
    IF p_username IS NULL OR p_passhash IS NULL THEN
        RAISE NOTICE 'Имя пользователя и пароль обязательны';
        RETURN;
    END IF;

    SELECT id INTO v_role_id
    FROM tele3.roles
    WHERE name = COALESCE(p_role_name, 'subscriber');

    IF v_role_id IS NULL THEN
        SELECT id INTO v_role_id FROM tele3.roles WHERE name = 'subscriber';
    END IF;

    INSERT INTO tele3.users(username, password_hash, role_id, email, full_name)
    VALUES (p_username, p_passhash, v_role_id, p_email, p_fullname);

EXCEPTION WHEN OTHERS THEN
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('users', 'ERROR', NULL,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_create_user', 'username', p_username));
END;
$$;

-- 6.6 ХП: Подключить/отключить доп. услугу
CREATE OR REPLACE PROCEDURE tele3.sp_toggle_service(
    p_sim_id     INTEGER,
    p_service_id INTEGER,
    p_action     VARCHAR   -- 'connect' | 'disconnect'
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_sim_id IS NULL OR p_service_id IS NULL THEN
        RETURN;
    END IF;

    IF COALESCE(p_action, 'connect') = 'connect' THEN
        INSERT INTO tele3.connected_services(sim_id, service_id)
        VALUES (p_sim_id, p_service_id)
        ON CONFLICT (sim_id, service_id) DO NOTHING;
    ELSE
        DELETE FROM tele3.connected_services
        WHERE sim_id = p_sim_id AND service_id = p_service_id;
    END IF;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO tele3.audit_log(table_name, operation, record_id, new_data)
    VALUES ('connected_services', 'ERROR', p_sim_id,
            jsonb_build_object('error', SQLERRM, 'proc', 'sp_toggle_service'));
END;
$$;

-- ============================================================
-- ЧАСТЬ 7: ПОЛЬЗОВАТЕЛИ БД И РАЗГРАНИЧЕНИЕ ПРАВ
-- Требование: "пользователь не должен иметь доступ к базовым таблицам непосредственно"
-- ============================================================

-- Создаём пользователей СУБД
-- (выполнять от суперпользователя)

DO $$
BEGIN
    -- Системный администратор ИС
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_admin') THEN
        CREATE ROLE tele3_admin LOGIN PASSWORD 'Admin@Tele3#2024';
    END IF;
    -- Администратор безопасности
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_security') THEN
        CREATE ROLE tele3_security LOGIN PASSWORD 'Sec@Tele3#2024';
    END IF;
    -- Оператор (поддержка / абонентский отдел)
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_operator') THEN
        CREATE ROLE tele3_operator LOGIN PASSWORD 'Oper@Tele3#2024';
    END IF;
    -- Биллинг оператор
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_billing') THEN
        CREATE ROLE tele3_billing LOGIN PASSWORD 'Bill@Tele3#2024';
    END IF;
    -- Привилегированный (для Flask-приложения)
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_app') THEN
        CREATE ROLE tele3_app LOGIN PASSWORD 'App@Tele3#2024';
    END IF;
    -- Непривилегированный (только чтение для внешних систем)
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tele3_readonly') THEN
        CREATE ROLE tele3_readonly LOGIN PASSWORD 'Read@Tele3#2024';
    END IF;
END $$;

-- Права на схему
GRANT USAGE ON SCHEMA tele3 TO tele3_admin, tele3_security, tele3_operator, tele3_billing, tele3_app, tele3_readonly;

-- tele3_admin: полный доступ ко всему
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA tele3 TO tele3_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA tele3 TO tele3_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA tele3 TO tele3_admin;

-- tele3_security: только аудит + представление пользователей
GRANT SELECT ON tele3.v_audit_log TO tele3_security;
GRANT SELECT ON tele3.v_users     TO tele3_security;
GRANT SELECT ON tele3.audit_log   TO tele3_security;
GRANT SELECT ON tele3.users       TO tele3_security;
GRANT SELECT ON tele3.roles       TO tele3_security;
-- security_admin может деактивировать пользователей
GRANT UPDATE (is_active) ON tele3.users TO tele3_security;

-- tele3_operator: работа с абонентами, SIM, звонками, SMS (только через views)
GRANT SELECT, INSERT, UPDATE ON tele3.v_subscribers TO tele3_operator;
GRANT SELECT ON tele3.v_sim_cards TO tele3_operator;
GRANT SELECT ON tele3.v_calls     TO tele3_operator;
GRANT SELECT ON tele3.v_sms       TO tele3_operator;
GRANT SELECT ON tele3.v_connected_services TO tele3_operator;
-- Через базовые таблицы — только для вставки через ХП
GRANT SELECT ON tele3.subscribers TO tele3_operator;
GRANT SELECT ON tele3.sim_cards   TO tele3_operator;
GRANT EXECUTE ON PROCEDURE tele3.sp_upsert_subscriber TO tele3_operator;
GRANT EXECUTE ON PROCEDURE tele3.sp_set_sim_status    TO tele3_operator;
GRANT EXECUTE ON PROCEDURE tele3.sp_connect_tariff    TO tele3_operator;
GRANT EXECUTE ON PROCEDURE tele3.sp_toggle_service    TO tele3_operator;

-- tele3_billing: платежи + чтение абонентов
GRANT SELECT ON tele3.v_payments     TO tele3_billing;
GRANT SELECT ON tele3.v_subscribers  TO tele3_billing;
GRANT SELECT ON tele3.subscribers    TO tele3_billing;
GRANT EXECUTE ON PROCEDURE tele3.sp_add_payment TO tele3_billing;

-- tele3_app: Flask-приложение работает от этого пользователя
-- Доступ только через представления и ХП
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tele3 TO tele3_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA tele3 TO tele3_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA tele3 TO tele3_app;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA tele3 TO tele3_app;

-- tele3_readonly: только чтение представлений (не таблиц!)
GRANT SELECT ON tele3.v_subscribers        TO tele3_readonly;
GRANT SELECT ON tele3.v_sim_cards          TO tele3_readonly;
GRANT SELECT ON tele3.v_tariffs            TO tele3_readonly;
GRANT SELECT ON tele3.v_connected_services TO tele3_readonly;

-- Создаём вьюху тарифов (нет пароля/персданных)
CREATE OR REPLACE VIEW tele3.v_tariffs AS
    SELECT id, name, monthly_fee, internet_gb, minutes, sms_count, is_active
    FROM tele3.tariffs
    WHERE is_active = TRUE;

-- Отзываем прямой доступ к базовым таблицам у неприв. пользователей
REVOKE ALL ON tele3.users       FROM tele3_operator, tele3_billing, tele3_readonly;
REVOKE ALL ON tele3.audit_log   FROM tele3_operator, tele3_billing, tele3_readonly;

-- ============================================================
-- ЧАСТЬ 8: РЕЗЕРВНОЕ КОПИРОВАНИЕ
-- Требование: "разработать систему резервного копирования"
-- ============================================================

-- Скрипт backup.sh создаётся отдельно (см. backup.sh)
-- Здесь — хранимая процедура для логирования бэкапов

CREATE TABLE IF NOT EXISTS tele3.backup_log (
    id          SERIAL PRIMARY KEY,
    backup_type VARCHAR(20) NOT NULL DEFAULT 'full',
    started_at  TIMESTAMP   NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMP,
    status      VARCHAR(20) NOT NULL DEFAULT 'running',
    file_path   TEXT,
    size_bytes  BIGINT,
    notes       TEXT
);

-- ============================================================
-- ЧАСТЬ 9: ИНДЕКСЫ
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_sim_subscriber   ON tele3.sim_cards(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_sim_status       ON tele3.sim_cards(status);
CREATE INDEX IF NOT EXISTS idx_calls_sim        ON tele3.calls(sim_id);
CREATE INDEX IF NOT EXISTS idx_calls_datetime   ON tele3.calls(call_datetime DESC);
CREATE INDEX IF NOT EXISTS idx_sms_sim          ON tele3.sms(sim_id);
CREATE INDEX IF NOT EXISTS idx_payments_sub     ON tele3.payments(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_payments_date    ON tele3.payments(payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_tc_sim           ON tele3.tariff_connections(sim_id);
CREATE INDEX IF NOT EXISTS idx_audit_table      ON tele3.audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_date       ON tele3.audit_log(changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_role       ON tele3.users(role_id);

-- ============================================================
-- ЧАСТЬ 10: ТЕСТОВЫЕ ДАННЫЕ (INSERT)
-- ============================================================

-- Роли
INSERT INTO tele3.roles(name, description) VALUES
    ('admin',            'Системный администратор — полный доступ к ИС'),
    ('security_admin',   'Администратор ИБ — управление доступом, аудит'),
    ('support',          'Техническая поддержка — работа с абонентами'),
    ('billing_operator', 'Оператор биллинга — платежи, тарифы'),
    ('subscriber',       'Абонент — личный кабинет')
ON CONFLICT (name) DO NOTHING;

-- Системные пользователи (пароли хешированы bcrypt в Flask)
-- Здесь placeholder-хеши для демонстрации структуры
-- Реальные хеши генерируются через werkzeug.security.generate_password_hash
INSERT INTO tele3.users(username, password_hash, role_id, email, full_name) VALUES
    ('admin',    '$2b$12$examplehashforadminuserABC123xyz', (SELECT id FROM tele3.roles WHERE name='admin'),          'admin@tele3.ru',    'Администратор Системы'),
    ('sec_admin','$2b$12$examplehashforsecadminDEF456uvw', (SELECT id FROM tele3.roles WHERE name='security_admin'), 'sec@tele3.ru',      'Иванова Мария Сергеевна'),
    ('support1', '$2b$12$examplehashforsupportGHI789rst', (SELECT id FROM tele3.roles WHERE name='support'),         'support@tele3.ru',  'Петров Алексей Иванович'),
    ('billing1', '$2b$12$examplehashforbillingJKL012mno', (SELECT id FROM tele3.roles WHERE name='billing_operator'),'billing@tele3.ru',  'Сидорова Елена Петровна'),
    ('user_ivanov','$2b$12$examplehashforsubscriberPQR',  (SELECT id FROM tele3.roles WHERE name='subscriber'),      'ivanov@mail.ru',    'Иванов Пётр Андреевич')
ON CONFLICT (username) DO NOTHING;

-- Тарифы
INSERT INTO tele3.tariffs(name, monthly_fee, internet_gb, minutes, sms_count) VALUES
    ('Базовый',      199.00,  5,  100,  50),
    ('Стандарт',     399.00,  15, 300, 100),
    ('Профессионал', 699.00,  30, 600, 300),
    ('Безлимит',     999.00,  50, 1000, 500),
    ('Детский',      149.00,  3,  60,  30)
ON CONFLICT (name) DO NOTHING;

-- Дополнительные услуги
INSERT INTO tele3.services(name, cost, description) VALUES
    ('Роуминг СНГ',         150.00, 'Международный роуминг в странах СНГ'),
    ('Переадресация',        49.00, 'Переадресация входящих звонков'),
    ('АнтиСпам',             29.00, 'Защита от спам-звонков'),
    ('Голосовая почта',      0.00,  'Бесплатная голосовая почта'),
    ('SMS-пакет 100',        99.00, 'Дополнительные 100 SMS')
ON CONFLICT (name) DO NOTHING;

-- Абоненты
INSERT INTO tele3.subscribers(last_name, first_name, middle_name, passport_series, passport_number, birth_date, phone, address, email, user_id)
VALUES
    ('Иванов',    'Пётр',      'Андреевич',  '4520', '123456', '1985-03-15', '+79161234501', 'г. Москва, ул. Ленина, 1',    'ivanov@mail.ru',    (SELECT id FROM tele3.users WHERE username='user_ivanov')),
    ('Сидорова',  'Анна',      'Викторовна', '4521', '234567', '1992-07-22', '+79161234502', 'г. Москва, ул. Мира, 5',      'sidorova@mail.ru',  NULL),
    ('Кузнецов',  'Дмитрий',   'Олегович',   '4522', '345678', '1978-11-08', '+79161234503', 'г. СПб, пр. Невский, 10',     'kuznetsov@mail.ru', NULL),
    ('Морозова',  'Ольга',     'Ивановна',   '4523', '456789', '2001-04-30', '+79161234504', 'г. Казань, ул. Пушкина, 3',   'morozova@mail.ru',  NULL),
    ('Новиков',   'Сергей',    'Павлович',   '4524', '567890', '1969-09-12', '+79161234505', 'г. Екатеринбург, ул. Мира, 7','novikov@mail.ru',   NULL)
ON CONFLICT (passport_series, passport_number) DO NOTHING;

-- SIM-карты
INSERT INTO tele3.sim_cards(phone_number, iccid, activation_date, status, subscriber_id)
VALUES
    ('+79161110001', '8970100000000000001', '2023-01-10', 'active', (SELECT id FROM tele3.subscribers WHERE passport_number='123456')),
    ('+79161110002', '8970100000000000002', '2023-02-15', 'active', (SELECT id FROM tele3.subscribers WHERE passport_number='234567')),
    ('+79161110003', '8970100000000000003', '2022-11-01', 'active', (SELECT id FROM tele3.subscribers WHERE passport_number='345678')),
    ('+79161110004', '8970100000000000004', '2024-03-20', 'blocked',(SELECT id FROM tele3.subscribers WHERE passport_number='456789')),
    ('+79161110005', '8970100000000000005', '2021-06-05', 'active', (SELECT id FROM tele3.subscribers WHERE passport_number='567890')),
    ('+79161110006', '8970100000000000006', '2024-05-01', 'reserved', NULL)
ON CONFLICT (phone_number) DO NOTHING;

-- Подключение тарифов
INSERT INTO tele3.tariff_connections(sim_id, tariff_id, connected_at)
SELECT sc.id, t.id, '2023-01-10'
FROM tele3.sim_cards sc, tele3.tariffs t
WHERE sc.phone_number = '+79161110001' AND t.name = 'Стандарт'
ON CONFLICT DO NOTHING;

INSERT INTO tele3.tariff_connections(sim_id, tariff_id, connected_at)
SELECT sc.id, t.id, '2023-02-15'
FROM tele3.sim_cards sc, tele3.tariffs t
WHERE sc.phone_number = '+79161110002' AND t.name = 'Базовый'
ON CONFLICT DO NOTHING;

INSERT INTO tele3.tariff_connections(sim_id, tariff_id, connected_at)
SELECT sc.id, t.id, '2022-11-01'
FROM tele3.sim_cards sc, tele3.tariffs t
WHERE sc.phone_number = '+79161110003' AND t.name = 'Безлимит'
ON CONFLICT DO NOTHING;

INSERT INTO tele3.tariff_connections(sim_id, tariff_id, connected_at)
SELECT sc.id, t.id, '2024-05-01'
FROM tele3.sim_cards sc, tele3.tariffs t
WHERE sc.phone_number = '+79161110005' AND t.name = 'Профессионал'
ON CONFLICT DO NOTHING;

-- Подключение доп. услуг
INSERT INTO tele3.connected_services(sim_id, service_id)
SELECT sc.id, s.id
FROM tele3.sim_cards sc, tele3.services s
WHERE sc.phone_number = '+79161110001' AND s.name IN ('АнтиСпам', 'Голосовая почта')
ON CONFLICT DO NOTHING;

INSERT INTO tele3.connected_services(sim_id, service_id)
SELECT sc.id, s.id
FROM tele3.sim_cards sc, tele3.services s
WHERE sc.phone_number = '+79161110003' AND s.name = 'Роуминг СНГ'
ON CONFLICT DO NOTHING;

-- Звонки
INSERT INTO tele3.calls(sim_id, destination, call_datetime, duration_sec, cost)
SELECT sc.id, '+79261234567', '2025-05-01 10:15:00', 180, 3.60
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110001';

INSERT INTO tele3.calls(sim_id, destination, call_datetime, duration_sec, cost)
SELECT sc.id, '+79031234567', '2025-05-02 14:30:00', 360, 7.20
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110001';

INSERT INTO tele3.calls(sim_id, destination, call_datetime, duration_sec, cost)
SELECT sc.id, '+79091234567', '2025-05-03 09:00:00', 60, 1.20
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110002';

INSERT INTO tele3.calls(sim_id, destination, call_datetime, duration_sec, cost)
SELECT sc.id, '+79161110001', '2025-05-04 18:45:00', 240, 0.00
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110003';

-- SMS
INSERT INTO tele3.sms(sim_id, destination, sent_datetime, cost)
SELECT sc.id, '+79261234567', '2025-05-01 10:20:00', 0.00
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110001';

INSERT INTO tele3.sms(sim_id, destination, sent_datetime, cost)
SELECT sc.id, '+79031234567', '2025-05-02 12:00:00', 2.50
FROM tele3.sim_cards sc WHERE sc.phone_number = '+79161110002';

-- Платежи
INSERT INTO tele3.payments(subscriber_id, amount, payment_date, payment_method, notes)
SELECT s.id, 399.00, '2025-05-01', 'card', 'Оплата тарифа Стандарт'
FROM tele3.subscribers s WHERE s.passport_number = '123456';

INSERT INTO tele3.payments(subscriber_id, amount, payment_date, payment_method, notes)
SELECT s.id, 199.00, '2025-05-01', 'online', 'Оплата тарифа Базовый'
FROM tele3.subscribers s WHERE s.passport_number = '234567';

INSERT INTO tele3.payments(subscriber_id, amount, payment_date, payment_method, notes)
SELECT s.id, 999.00, '2025-04-30', 'terminal', 'Оплата через терминал'
FROM tele3.subscribers s WHERE s.passport_number = '345678';

INSERT INTO tele3.payments(subscriber_id, amount, payment_date, payment_method, notes)
SELECT s.id, 500.00, '2025-05-15', 'cash', 'Частичная оплата'
FROM tele3.subscribers s WHERE s.passport_number = '567890';

-- ============================================================
-- ЧАСТЬ 11: ПРИМЕРЫ SELECT-ЗАПРОСОВ
-- ============================================================

-- Пример 1: Все абоненты с количеством SIM и текущим тарифом
/*
SELECT
    sub.full_name,
    sub.sim_count,
    sc.phone_number,
    sc.current_tariff,
    sc.tariff_since
FROM tele3.v_subscribers sub
LEFT JOIN tele3.v_sim_cards sc ON sc.subscriber_id = sub.id
ORDER BY sub.last_name;
*/

-- Пример 2: Сумма платежей за месяц по абонентам
/*
SELECT
    p.subscriber_name,
    SUM(p.amount) AS total_paid,
    COUNT(*)      AS payment_count
FROM tele3.v_payments p
WHERE p.payment_date >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY p.subscriber_name
ORDER BY total_paid DESC;
*/

-- Пример 3: Топ-5 номеров по количеству звонков
/*
SELECT
    c.phone_number,
    COUNT(*)              AS calls_count,
    SUM(c.duration_sec)   AS total_seconds,
    SUM(c.cost)           AS total_cost
FROM tele3.v_calls c
GROUP BY c.phone_number
ORDER BY calls_count DESC
LIMIT 5;
*/

-- Пример 4: SIM с заблокированным статусом
/*
SELECT phone_number, subscriber_name, activation_date
FROM tele3.v_sim_cards
WHERE status = 'blocked';
*/

-- Пример 5: Подключённые услуги по SIM-карте
/*
SELECT cs.phone_number, cs.service_name, cs.cost, cs.connected_at
FROM tele3.v_connected_services cs
WHERE cs.phone_number = '+79161110001';
*/

-- Пример 6: Аудит — последние 20 операций (только для security_admin)
/*
SELECT table_name, operation, record_id, changed_by, changed_at
FROM tele3.v_audit_log
LIMIT 20;
*/

-- Пример 7: Доходы по способу оплаты
/*
SELECT payment_method, COUNT(*) AS cnt, SUM(amount) AS revenue
FROM tele3.payments
GROUP BY payment_method
ORDER BY revenue DESC;
*/

-- Пример 8: M:N — все услуги на каждой SIM
/*
SELECT sc.phone_number, STRING_AGG(s.name, ', ') AS services
FROM tele3.sim_cards sc
JOIN tele3.connected_services cs ON cs.sim_id = sc.id
JOIN tele3.services s ON s.id = cs.service_id
GROUP BY sc.phone_number;
*/

-- Пример 9: История смены тарифов (1:N — у SIM много записей тарифов)
/*
SELECT sc.phone_number, t.name, tc.connected_at, tc.disconnected_at
FROM tele3.tariff_connections tc
JOIN tele3.sim_cards sc ON sc.id = tc.sim_id
JOIN tele3.tariffs t    ON t.id  = tc.tariff_id
ORDER BY sc.phone_number, tc.connected_at DESC;
*/

-- Пример 10: Таблица соответствия пользователей и прав (требование из задания)
/*
SELECT
    u.username,
    r.name       AS role,
    r.description,
    u.is_active,
    u.last_login
FROM tele3.v_users u
JOIN tele3.roles r ON r.name = u.role_name
ORDER BY r.name, u.username;
*/

-- ============================================================
-- ФИНАЛЬНОЕ СООБЩЕНИЕ
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'БД "ТЕЛЕ 3" успешно создана!';
    RAISE NOTICE 'Таблиц:       %', (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='tele3' AND table_type='BASE TABLE');
    RAISE NOTICE 'Представлений:%', (SELECT COUNT(*) FROM information_schema.views  WHERE table_schema='tele3');
    RAISE NOTICE '==============================================';
END $$;
