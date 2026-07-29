from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query, execute, call_proc
from app.auth import role_required, login_required
from app.routes.utils import get_page

bp = Blueprint('sim', __name__)
ALLOWED = ('admin', 'support', 'security_admin', 'billing_operator')


@bp.route('/')
@login_required
@role_required(*ALLOWED)
def index():
    search   = request.args.get('q', '').strip()
    status_f = request.args.get('status', '')
    page     = max(1, int(request.args.get('page', 1)))
    per_page = 20
    offset   = (page - 1) * per_page

    conds, params = [], []
    if search:
        conds.append("(phone_number ILIKE %s OR subscriber_name ILIKE %s)")
        params += [f'%{search}%', f'%{search}%']
    if status_f:
        conds.append("status = %s")
        params.append(status_f)

    where = ('WHERE ' + ' AND '.join(conds)) if conds else ''
    try:
        rows  = query(
            f"SELECT * FROM tele3.v_sim_cards {where} ORDER BY phone_number LIMIT %s OFFSET %s",
            params + [per_page, offset], fetch='all') or []
        total_row = query(
            f"SELECT COUNT(*) AS cnt FROM tele3.v_sim_cards {where}", params, fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        flash(f'Ошибка загрузки SIM-карт: {e}', 'danger')
        rows, total = [], 0

    return render_template('sim/index.html',
        sim_cards=rows, search=search, status_f=status_f,
        page=page, per_page=per_page, total=total)


@bp.route('/<int:sim_id>')
@login_required
@role_required(*ALLOWED)
def detail(sim_id):
    try:
        sim = query("SELECT * FROM tele3.v_sim_cards WHERE id = %s", (sim_id,), fetch='one')
    except Exception as e:
        flash(f'Ошибка загрузки SIM: {e}', 'danger')
        return redirect(url_for('sim.index'))

    if not sim:
        flash('SIM-карта не найдена.', 'danger')
        return redirect(url_for('sim.index'))

    try:
        tariff_history = query(
            """SELECT tc.*, t.name AS tariff_name FROM tele3.tariff_connections tc
               JOIN tele3.tariffs t ON t.id = tc.tariff_id
               WHERE tc.sim_id = %s ORDER BY tc.connected_at DESC""",
            (sim_id,), fetch='all') or []
    except Exception:
        tariff_history = []

    try:
        services = query(
            "SELECT * FROM tele3.v_connected_services WHERE sim_id = %s", (sim_id,), fetch='all') or []
    except Exception:
        services = []

    try:
        tariffs  = query("SELECT * FROM tele3.tariffs WHERE is_active = TRUE ORDER BY monthly_fee", fetch='all') or []
    except Exception:
        tariffs = []

    try:
        all_svcs = query("SELECT * FROM tele3.services WHERE is_active = TRUE ORDER BY name", fetch='all') or []
    except Exception:
        all_svcs = []

    return render_template('sim/detail.html',
        sim=sim, tariff_history=tariff_history,
        services=services, tariffs=tariffs, all_svcs=all_svcs)


@bp.route('/create', methods=['GET', 'POST'])
@login_required
@role_required('admin', 'support')
def create():
    subscribers = query("SELECT id, last_name, first_name FROM tele3.subscribers ORDER BY last_name", fetch='all') or []
    if request.method == 'POST':
        f = request.form
        try:
            from datetime import date
            act_date = date.fromisoformat(f.get('activation_date')) if f.get('activation_date') else date.today()
            execute(
                """INSERT INTO tele3.sim_cards(phone_number, iccid, activation_date, status, subscriber_id)
                   VALUES (%s, %s, %s, %s, %s)""",
                (f.get('phone_number','').strip(),
                 f.get('iccid','').strip() or None,
                 act_date,
                 f.get('status','active'),
                 int(f['subscriber_id']) if f.get('subscriber_id') else None)
            )
            flash('SIM-карта добавлена.', 'success')
            return redirect(url_for('sim.index'))
        except Exception as e:
            flash('Ошибка при добавлении SIM-карты. Проверьте уникальность номера.', 'danger')

    return render_template('sim/form.html', sim=None, subscribers=subscribers)


@bp.route('/<int:sim_id>/set_status', methods=['POST'])
@login_required
@role_required('admin', 'support')
def set_status(sim_id):
    status = request.form.get('status', 'active')
    try:
        call_proc('tele3.sp_set_sim_status', (sim_id, status))
        flash(f'Статус SIM обновлён: {status}.', 'success')
    except Exception as e:
        flash(f'Ошибка обновления статуса: {e}', 'danger')
    return redirect(url_for('sim.detail', sim_id=sim_id))


@bp.route('/<int:sim_id>/connect_tariff', methods=['POST'])
@login_required
@role_required('admin', 'support', 'billing_operator')
def connect_tariff(sim_id):
    tariff_id = request.form.get('tariff_id')
    if not tariff_id:
        flash('Выберите тариф.', 'warning')
        return redirect(url_for('sim.detail', sim_id=sim_id))
    try:
        call_proc('tele3.sp_connect_tariff', (sim_id, int(tariff_id)))
        flash('Тариф подключён.', 'success')
    except Exception as e:
        flash(f'Ошибка подключения тарифа: {e}', 'danger')
    return redirect(url_for('sim.detail', sim_id=sim_id))


@bp.route('/<int:sim_id>/toggle_service', methods=['POST'])
@login_required
@role_required('admin', 'support')
def toggle_service(sim_id):
    service_id = request.form.get('service_id')
    action     = request.form.get('action', 'connect')
    if not service_id:
        flash('Выберите услугу.', 'warning')
        return redirect(url_for('sim.detail', sim_id=sim_id))
    try:
        call_proc('tele3.sp_toggle_service', (sim_id, int(service_id), action))
        flash('Услуга обновлена.', 'success')
    except Exception as e:
        flash(f'Ошибка обновления услуги: {e}', 'danger')
    return redirect(url_for('sim.detail', sim_id=sim_id))
