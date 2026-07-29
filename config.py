import os


class Config:
    """Конфигурация приложения из переменных окружения."""

    # Значение по умолчанию допустимо только для локального запуска.
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-only-change-me")

    DB_HOST = os.environ.get("DB_HOST", "localhost")
    DB_PORT = os.environ.get("DB_PORT", "5432")
    DB_NAME = os.environ.get("DB_NAME", "tele3")
    DB_USER = os.environ.get("DB_USER", "tele3_app")
    DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
    DB_SCHEMA = os.environ.get("DB_SCHEMA", "tele3")

    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    PERMANENT_SESSION_LIFETIME = 3600
