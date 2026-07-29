"""
run.py — точка запуска Flask-приложения «ТЕЛЕ 3».
Запуск: python3 run.py
"""
from app import create_app

app = create_app()

if __name__ == '__main__':
    # host='0.0.0.0' — доступ с клиентской VM2
    # debug=False в продакшене!
    app.run(host='0.0.0.0', port=5000, debug=False)
