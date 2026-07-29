"""
subscriber_routes.py — управление абонентами.
Доступ: admin, support, billing_operator, security_admin
"""
from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query, execute, call_proc
from app.auth import role_required, login_required

bp = Blueprint('subscribers', __name__)

ALLOWED = ('admin', 'support', 'billing_operator', 'security_admin')


@bp.route('/')
@login_required
@role_required(*ALLOWED)
def index():
    search = request.args.get('q', '').strip()
    page   = max(1, int(request.args.get('page', 1)))
    per_page = 20
    offset   = (page - 1) * per_page

    try:
        if search:
            rows = query(
                """SELECT * FROM tele3.v_subscribers
                   WHERE last_name ILIKE %s OR first_name ILIKE %s
                      OR passport_number ILIKE %s OR phone ILIKE %s
                   ORDER BY last_name LIMIT %s OFFSET %s""",
                (f'%{search}%', f'%{search}%', f'%{search}%', f'%{search}%', per_page, offset),
                fetch='all') or []
            total_row = query(
                """SELECT COUNT(*) AS cnt FROM tele3.v_subscribers
                   WHERE last_name ILIKE %s OR first_name ILIKE %s
                      OR passport_number ILIKE %s OR phone ILIKE %s""",
                (f'%{search}%', f'%{search}%', f'%{search}%', f'%{search}%'), fetch='one')
        else:
            rows  = query("SELECT * FROM tele3.v_subscribers ORDER BY last_name LIMIT %s OFFSET %s",
                          (per_page, offset), fetch='all') or []
            total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_subscribers", fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        flash(f'Ошибка загрузки абонентов: {e}', 'danger')
        rows, total = [], 0

    return render_template('subscribers/index.html',
                           subscribers=rows, search=search,
                           page=page, per_page=per_page, total=total)


@bp.route('/<int:sub_id>')
@login_required
@role_required(*ALLOWED)
def detail(sub_id):
    try:
        sub = query("SELECT * FROM tele3.v_subscribers WHERE id = %s", (sub_id,), fetch='one')
    except Exception as e:
        flash(f'Ошибка загрузки абонента: {e}', 'danger')
        return redirect(url_for('subscribers.index'))

    if not sub:
        flash('Абонент не найден.', 'danger')
        return redirect(url_for('subscribers.index'))

    try:
        sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id = %s", (sub_id,), fetch='all') or []
    except Exception:
        sim_cards = []

    try:
        payments  = query(
            "SELECT * FROM tele3.v_payments WHERE subscriber_id = %s ORDER BY payment_date DESC LIMIT 10",
            (sub_id,), fetch='all') or []
    except Exception:
        payments = []

    return render_template('subscribers/detail.html',
                           sub=sub, sim_cards=sim_cards, payments=payments)


@bp.route('/create', methods=['GET', 'POST'])
@login_required
@role_required('admin', 'support')
def create():
    if request.method == 'POST':
        f = request.form
        try:
            from datetime import date
            birth_date = date.fromisoformat(f.get('birth_date', '')) if f.get('birth_date') else None
            call_proc('tele3.sp_upsert_subscriber', (
                None,
                f.get('last_name', '').strip(),
                f.get('first_name', '').strip(),
                f.get('middle_name', '').strip() or None,
                f.get('passport_series', '').strip(),
                f.get('passport_number', '').strip(),
                birth_date,
                f.get('phone', '').strip() or None,
                f.get('address', '').strip() or None,
                f.get('email', '').strip() or None,
            ))
            flash('Абонент добавлен.', 'success')
            return redirect(url_for('subscribers.index'))
        except Exception as e:
            flash(f'Ошибка при добавлении абонента: {e}', 'danger')

    return render_template('subscribers/form.html', sub=None)


@bp.route('/<int:sub_id>/edit', methods=['GET', 'POST'])
@login_required
@role_required('admin', 'support')
def edit(sub_id):
    sub = query("SELECT * FROM tele3.subscribers WHERE id = %s", (sub_id,), fetch='one')
    if not sub:
        flash('Абонент не найден.', 'danger')
        return redirect(url_for('subscribers.index'))

    if request.method == 'POST':
        f = request.form
        try:
            from datetime import date
            birth_date = date.fromisoformat(f.get('birth_date', '')) if f.get('birth_date') else None
            call_proc('tele3.sp_upsert_subscriber', (
                sub_id,
                f.get('last_name', '').strip() or None,
                f.get('first_name', '').strip() or None,
                f.get('middle_name', '').strip() or None,
                f.get('passport_series', '').strip() or None,
                f.get('passport_number', '').strip() or None,
                birth_date,
                f.get('phone', '').strip() or None,
                f.get('address', '').strip() or None,
                f.get('email', '').strip() or None,
            ))
            flash('Данные абонента обновлены.', 'success')
            return redirect(url_for('subscribers.detail', sub_id=sub_id))
        except Exception as e:
            flash(f'Ошибка при обновлении данных: {e}', 'danger')

    return render_template('subscribers/form.html', sub=sub)


@bp.route('/<int:sub_id>/delete', methods=['POST'])
@login_required
@role_required('admin')
def delete(sub_id):
    try:
        execute("DELETE FROM tele3.subscribers WHERE id = %s", (sub_id,))
        flash('Абонент удалён.', 'success')
    except Exception:
        flash('Ошибка при удалении. Возможно, у абонента есть связанные данные.', 'danger')
    return redirect(url_for('subscribers.index'))
