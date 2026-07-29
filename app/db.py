import psycopg2
import psycopg2.extras
from flask import g, current_app


def get_db():
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
    db = g.pop('db', None)
    if db is not None:
        db.close()


def query(sql, params=None, fetch='all'):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            if fetch == 'all':
                return cur.fetchall()
            if fetch == 'one':
                return cur.fetchone()
            conn.commit()
            return None
    except Exception as e:
        conn.rollback()
        current_app.logger.exception("Ошибка запроса к базе данных")
        raise


def execute(sql, params=None):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            conn.commit()
            return cur.fetchone() if cur.description else None
    except Exception as e:
        conn.rollback()
        current_app.logger.exception("Ошибка изменения данных в базе")
        raise


def call_proc(proc_name, params=None):
    conn = get_db()
    placeholders = ', '.join(['%s'] * len(params)) if params else ''
    sql = f"CALL {proc_name}({placeholders})"
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            conn.commit()
    except Exception as e:
        conn.rollback()
        current_app.logger.exception("Ошибка вызова процедуры %s", proc_name)
        raise


def init_app(app):
    app.teardown_appcontext(close_db)
