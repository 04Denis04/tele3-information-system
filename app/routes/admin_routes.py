"""
admin_routes.py — административная панель.
Доступ: admin, security_admin
"""
from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from werkzeug.security import generate_password_hash
from app.db import query, execute, call_proc
from app.auth import role_required, login_required

bp = Blueprint('admin', __name__)


@bp.route('/')
@login_required
@role_required('admin', 'security_admin')
def dashboard():
    try:
        stats = {
            'subscribers': (query("SELECT COUNT(*) AS cnt FROM tele3.subscribers", fetch='one') or {}).get('cnt', 0),
            'sim_cards':   (query("SELECT COUNT(*) AS cnt FROM tele3.sim_cards", fetch='one') or {}).get('cnt', 0),
            'active_sim':  (query("SELECT COUNT(*) AS cnt FROM tele3.sim_cards WHERE status='active'", fetch='one') or {}).get('cnt', 0),
            'payments_month': (query(
                "SELECT COALESCE(SUM(amount),0) AS s FROM tele3.payments WHERE payment_date >= DATE_TRUNC('month', CURRENT_DATE)",
                fetch='one') or {}).get('s', 0),
            'calls_today': (query(
                "SELECT COUNT(*) AS cnt FROM tele3.calls WHERE call_datetime::date = CURRENT_DATE",
                fetch='one') or {}).get('cnt', 0),
            'users': (query("SELECT COUNT(*) AS cnt FROM tele3.users", fetch='one') or {}).get('cnt', 0),
        }
    except Exception as e:
        stats = {}
        flash(f'Ошибка загрузки статистики: {e}', 'warning')

    try:
        recent_audit = query("SELECT * FROM tele3.v_audit_log LIMIT 10", fetch='all') or [] \
            if session.get('role') in ('security_admin', 'admin') else []
    except Exception:
        recent_audit = []

    return render_template('admin/dashboard.html', stats=stats, recent_audit=recent_audit)


# ── Управление пользователями ────────────────────────────────

@bp.route('/users')
@login_required
@role_required('admin', 'security_admin')
def users():
    rows = query("SELECT * FROM tele3.v_users ORDER BY role_name, username", fetch='all') or []
    return render_template('admin/users.html', users=rows)


@bp.route('/users/create', methods=['GET', 'POST'])
@login_required
@role_required('admin', 'security_admin')
def user_create():
    roles = query("SELECT * FROM tele3.roles ORDER BY name", fetch='all') or []
    if request.method == 'POST':
        username  = request.form.get('username', '').strip()
        password  = request.form.get('password', '')
        role_name = request.form.get('role_name', 'subscriber')
        email     = request.form.get('email', '').strip() or None
        fullname  = request.form.get('full_name', '').strip() or None

        if not username or not password:
            flash('Логин и пароль обязательны.', 'warning')
            return render_template('admin/user_form.html', roles=roles, user=None)
        if len(password) < 6:
            flash('Пароль должен быть не менее 6 символов.', 'warning')
            return render_template('admin/user_form.html', roles=roles, user=None)

        try:
            ph = generate_password_hash(password)
            call_proc('tele3.sp_create_user', (username, ph, role_name, email, fullname))
            flash(f'Пользователь «{username}» создан.', 'success')
            return redirect(url_for('admin.users'))
        except Exception as e:
            flash(f'Ошибка при создании пользователя: {e}', 'danger')

    return render_template('admin/user_form.html', roles=roles, user=None)


@bp.route('/users/<int:user_id>/toggle', methods=['POST'])
@login_required
@role_required('admin', 'security_admin')
def user_toggle(user_id):
    user = query("SELECT id, is_active, username FROM tele3.users WHERE id = %s", (user_id,), fetch='one')
    if not user:
        flash('Пользователь не найден.', 'danger')
        return redirect(url_for('admin.users'))
    new_state = not user['is_active']
    execute("UPDATE tele3.users SET is_active = %s WHERE id = %s", (new_state, user_id))
    state_str = 'активирован' if new_state else 'деактивирован'
    flash(f'Пользователь «{user["username"]}» {state_str}.', 'success')
    return redirect(url_for('admin.users'))


@bp.route('/users/<int:user_id>/reset_password', methods=['POST'])
@login_required
@role_required('admin', 'security_admin')
def user_reset_password(user_id):
    new_pass = request.form.get('new_password', '')
    if len(new_pass) < 6:
        flash('Пароль должен быть не менее 6 символов.', 'warning')
        return redirect(url_for('admin.users'))
    ph = generate_password_hash(new_pass)
    execute("UPDATE tele3.users SET password_hash = %s WHERE id = %s", (ph, user_id))
    flash('Пароль сброшен.', 'success')
    return redirect(url_for('admin.users'))


# ── Аудит ───────────────────────────────────────────────────

@bp.route('/audit')
@login_required
@role_required('admin', 'security_admin')
def audit():
    table_filter = request.args.get('table', '')
    op_filter    = request.args.get('operation', '')
    page         = max(1, int(request.args.get('page', 1)))
    per_page     = 50
    offset       = (page - 1) * per_page

    conditions, params = [], []
    if table_filter:
        conditions.append("table_name = %s")
        params.append(table_filter)
    if op_filter:
        conditions.append("operation = %s")
        params.append(op_filter)

    where = ('WHERE ' + ' AND '.join(conditions)) if conditions else ''
    try:
        rows = query(
            f"SELECT * FROM tele3.audit_log {where} ORDER BY changed_at DESC LIMIT %s OFFSET %s",
            params + [per_page, offset], fetch='all') or []
        total_row = query(f"SELECT COUNT(*) AS cnt FROM tele3.audit_log {where}", params, fetch='one')
        total = total_row['cnt'] if total_row else 0
        tables = query("SELECT DISTINCT table_name FROM tele3.audit_log ORDER BY table_name", fetch='all') or []
    except Exception as e:
        rows, total, tables = [], 0, []
        flash(f'Ошибка загрузки аудита: {e}', 'warning')

    return render_template('admin/audit.html',
        rows=rows, total=total, page=page, per_page=per_page,
        tables=tables, table_filter=table_filter, op_filter=op_filter)


# ── Роли ─────────────────────────────────────────────────────

@bp.route('/roles')
@login_required
@role_required('admin', 'security_admin')
def roles():
    rows = query("SELECT * FROM tele3.roles ORDER BY id", fetch='all') or []
    return render_template('admin/roles.html', roles=rows)
