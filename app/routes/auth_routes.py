from flask import Blueprint, render_template, request, redirect, url_for, session, flash
from werkzeug.security import check_password_hash, generate_password_hash
from app.db import query, execute

bp = Blueprint('auth', __name__)


@bp.route('/')
def index():
    if 'user_id' in session:
        return redirect(url_for('auth.dashboard'))
    return redirect(url_for('auth.login'))


@bp.route('/login', methods=['GET', 'POST'])
def login():
    if 'user_id' in session:
        return redirect(url_for('auth.dashboard'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        if not username or not password:
            flash('Введите логин и пароль.', 'warning')
            return render_template('auth/login.html')
        user = query(
            """SELECT u.id, u.username, u.password_hash, u.full_name,
                      u.is_active, r.name AS role
               FROM tele3.users u
               JOIN tele3.roles r ON r.id = u.role_id
               WHERE u.username = %s""",
            (username,), fetch='one'
        )

        if not user:
            flash('Неверный логин или пароль.', 'danger')
            return render_template('auth/login.html')

        if not user['is_active']:
            flash('Учётная запись деактивирована. Обратитесь к администратору.', 'danger')
            return render_template('auth/login.html')

        if not check_password_hash(user['password_hash'], password):
            flash('Неверный логин или пароль.', 'danger')
            return render_template('auth/login.html')
        session.permanent = True
        session['user_id']  = user['id']
        session['username'] = user['username']
        session['role']     = user['role']
        session['fullname'] = user['full_name'] or user['username']
        execute("UPDATE tele3.users SET last_login = NOW() WHERE id = %s", (user['id'],))

        flash(f'Добро пожаловать, {session["fullname"]}!', 'success')
        role = user['role']
        if role == 'admin':
            return redirect(url_for('admin.dashboard'))
        elif role == 'security_admin':
            return redirect(url_for('admin.audit'))
        elif role == 'subscriber':
            return redirect(url_for('cabinet.index'))
        else:
            return redirect(url_for('auth.dashboard'))

    return render_template('auth/login.html')


@bp.route('/logout')
def logout():
    session.clear()
    flash('Вы вышли из системы.', 'info')
    return redirect(url_for('auth.login'))


@bp.route('/dashboard')
def dashboard():
    if 'user_id' not in session:
        return redirect(url_for('auth.login'))
    role = session.get('role')
    if role == 'admin':
        return redirect(url_for('admin.dashboard'))
    elif role == 'security_admin':
        return redirect(url_for('admin.audit'))
    elif role == 'subscriber':
        return redirect(url_for('cabinet.index'))
    else:
        return redirect(url_for('subscribers.index'))
