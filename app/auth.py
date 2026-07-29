from functools import wraps
from flask import session, redirect, url_for, flash, abort


ROLE_HIERARCHY = {
    'admin':            5,
    'security_admin':   4,
    'billing_operator': 3,
    'support':          2,
    'subscriber':       1,
}


def login_required(f):
    """Требует авторизации. Перенаправляет на /login если не авторизован."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            flash('Для доступа необходимо войти в систему.', 'warning')
            return redirect(url_for('auth.login'))
        return f(*args, **kwargs)
    return decorated


def role_required(*roles):
    """
    Требует наличия одной из указанных ролей.
    Использование: @role_required('admin', 'security_admin')
    """
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if 'user_id' not in session:
                flash('Для доступа необходимо войти в систему.', 'warning')
                return redirect(url_for('auth.login'))
            user_role = session.get('role')
            if user_role not in roles:
                flash('Недостаточно прав для выполнения операции.', 'danger')
                abort(403)
            return f(*args, **kwargs)
        return decorated
    return decorator


def min_role(role_name):
    """Требует роль не ниже указанной в иерархии."""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if 'user_id' not in session:
                return redirect(url_for('auth.login'))
            user_level  = ROLE_HIERARCHY.get(session.get('role'), 0)
            needed_level = ROLE_HIERARCHY.get(role_name, 99)
            if user_level < needed_level:
                abort(403)
            return f(*args, **kwargs)
        return decorated
    return decorator


def current_user():
    return {
        'id':       session.get('user_id'),
        'username': session.get('username'),
        'role':     session.get('role'),
        'fullname': session.get('fullname'),
    }
