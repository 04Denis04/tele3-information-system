"""
db.py — управление подключением к PostgreSQL через psycopg2.
Все запросы параметризованы — защита от SQL-инъекций гарантирована.
"""
import psycopg2
import psycopg2.extras
from flask import g, current_app


def get_db():
    """Возвращает соединение из контекста запроса (создаёт при первом обращении)."""
    if 'db' not in g:
        cfg = current_app.config
        g.db = psycopg2.connect(
            host=cfg['DB_HOST'],
            port=cfg['DB_PORT'],
            dbname=cfg['DB_NAME'],
            user=cfg['DB_USER'],
            password=cfg['DB_PASSWORD'],
            options=f"-c search_path={cfg['DB_SCHEMA']},public",
            cursor_factory=psycopg2.extras.RealDictCursor
        )
        g.db.autocommit = False
    return g.db


def close_db(e=None):
    """Закрывает соединение в конце запроса."""
    db = g.pop('db', None)
    if db is not None:
        db.close()


def query(sql, params=None, fetch='all'):
    """
    Универсальная параметризованная выборка.
    fetch: 'all' | 'one' | 'none'
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            if fetch == 'all':
                return cur.fetchall()
            elif fetch == 'one':
                return cur.fetchone()
            else:
                conn.commit()
                return None
    except Exception as e:
        conn.rollback()
        current_app.logger.error(f"DB query error: {e} | SQL: {sql} | params: {params}")
        raise


def execute(sql, params=None):
    """Параметризованное изменение данных (INSERT/UPDATE/DELETE)."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            conn.commit()
            # Возвращаем lastrowid если есть RETURNING
            try:
                row = cur.fetchone()
                return row
            except Exception:
                return None
    except Exception as e:
        conn.rollback()
        current_app.logger.error(f"DB execute error: {e} | SQL: {sql} | params: {params}")
        raise


def call_proc(proc_name, params=None):
    """Вызов хранимой процедуры PostgreSQL."""
    conn = get_db()
    placeholders = ', '.join(['%s'] * len(params)) if params else ''
    sql = f"CALL {proc_name}({placeholders})"
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            conn.commit()
    except Exception as e:
        conn.rollback()
        current_app.logger.error(f"DB proc error: {e} | proc: {proc_name}")
        raise


def init_app(app):
    app.teardown_appcontext(close_db)
