"""tariff_routes.py"""
from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query, execute
from app.auth import role_required, login_required

bp = Blueprint('tariffs', __name__)

@bp.route('/')
@login_required
def index():
    rows = query("SELECT * FROM tele3.tariffs ORDER BY monthly_fee", fetch='all')
    return render_template('tariffs/index.html', tariffs=rows)

@bp.route('/create', methods=['GET','POST'])
@login_required
@role_required('admin', 'billing_operator')
def create():
    if request.method == 'POST':
        f = request.form
        try:
            execute(
                """INSERT INTO tele3.tariffs(name, monthly_fee, internet_gb, minutes, sms_count)
                   VALUES (%s,%s,%s,%s,%s)""",
                (f['name'].strip(), float(f.get('monthly_fee',0)),
                 int(f.get('internet_gb',0)), int(f.get('minutes',0)), int(f.get('sms_count',0)))
            )
            flash('Тариф добавлен.', 'success')
            return redirect(url_for('tariffs.index'))
        except Exception:
            flash('Ошибка при добавлении тарифа.', 'danger')
    return render_template('tariffs/form.html', tariff=None)

@bp.route('/<int:tid>/edit', methods=['GET','POST'])
@login_required
@role_required('admin', 'billing_operator')
def edit(tid):
    tariff = query("SELECT * FROM tele3.tariffs WHERE id=%s", (tid,), fetch='one')
    if not tariff:
        flash('Тариф не найден.', 'danger')
        return redirect(url_for('tariffs.index'))
    if request.method == 'POST':
        f = request.form
        try:
            execute(
                """UPDATE tele3.tariffs SET name=%s, monthly_fee=%s, internet_gb=%s,
                   minutes=%s, sms_count=%s WHERE id=%s""",
                (f['name'].strip(), float(f.get('monthly_fee',0)),
                 int(f.get('internet_gb',0)), int(f.get('minutes',0)),
                 int(f.get('sms_count',0)), tid)
            )
            flash('Тариф обновлён.', 'success')
            return redirect(url_for('tariffs.index'))
        except Exception:
            flash('Ошибка при обновлении.', 'danger')
    return render_template('tariffs/form.html', tariff=tariff)

@bp.route('/<int:tid>/toggle', methods=['POST'])
@login_required
@role_required('admin')
def toggle(tid):
    t = query("SELECT is_active FROM tele3.tariffs WHERE id=%s", (tid,), fetch='one')
    if t:
        execute("UPDATE tele3.tariffs SET is_active=%s WHERE id=%s", (not t['is_active'], tid))
        flash('Статус тарифа изменён.', 'success')
    return redirect(url_for('tariffs.index'))
