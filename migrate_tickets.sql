-- Таблица обращений в поддержку (если не существует)
CREATE TABLE IF NOT EXISTS tele3.tickets (
    id              SERIAL PRIMARY KEY,
    subscriber_id   INTEGER NOT NULL REFERENCES tele3.subscribers(id) ON DELETE CASCADE,
    subject         VARCHAR(200) NOT NULL,
    body            TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open','in_progress','closed')),
    support_comment TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    resolved_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_tickets_subscriber ON tele3.tickets(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status     ON tele3.tickets(status);

-- Таблица security_log (если не существует)
CREATE TABLE IF NOT EXISTS tele3.security_log (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES tele3.users(id),
    action     VARCHAR(100),
    details    TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Доступ для приложения
GRANT SELECT, INSERT, UPDATE ON tele3.tickets TO tele3_app;
GRANT USAGE, SELECT ON SEQUENCE tele3.tickets_id_seq TO tele3_app;
GRANT SELECT, INSERT ON tele3.security_log TO tele3_app;
GRANT USAGE, SELECT ON SEQUENCE tele3.security_log_id_seq TO tele3_app;
