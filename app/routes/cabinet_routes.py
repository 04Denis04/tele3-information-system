from flask import Blueprint, render_template, session, redirect, url_for, flash, request
from werkzeug.security import check_password_hash, generate_password_hash
from app.db import query, execute, call_proc
from app.auth import role_required, login_required
from app.routes.utils import get_page

bp = Blueprint('cabinet', __name__)


def _get_subscriber():
    """Вернуть запись subscriber для текущего пользователя."""
    return query("SELECT * FROM tele3.subscribers WHERE user_id=%s", (session['user_id'],), fetch='one')


def _log_security(action, details=''):
    """Запись в security_log / audit_log если таблица существует."""
    try:
        execute(
            """INSERT INTO tele3.security_log(user_id, action, details, created_at)
               VALUES (%s, %s, %s, NOW())""",
            (session['user_id'], action, details)
        )
    except Exception:
        pass  # таблица может называться иначе; не критично

@bp.route('/')
@login_required
@role_required('subscriber')
def index():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')

    try:
        sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id=%s ORDER BY phone_number",
                          (sub['id'],), fetch='all') or []
    except Exception:
        sim_cards = []

    try:
        payments = query(
            "SELECT * FROM tele3.v_payments WHERE subscriber_id=%s ORDER BY payment_date DESC LIMIT 5",
            (sub['id'],), fetch='all') or []
    except Exception:
        payments = []

    calls, sms_list = [], []
    if sim_cards:
        first_sim = sim_cards[0]['id']
        try:
            calls = query(
                "SELECT * FROM tele3.v_calls WHERE sim_id=%s ORDER BY call_datetime DESC LIMIT 10",
                (first_sim,), fetch='all') or []
        except Exception:
            calls = []
        try:
            sms_list = query(
                "SELECT * FROM tele3.v_sms WHERE sim_id=%s ORDER BY sent_datetime DESC LIMIT 10",
                (first_sim,), fetch='all') or []
        except Exception:
            sms_list = []

    try:
        tickets = query(
            "SELECT * FROM tele3.tickets WHERE subscriber_id=%s ORDER BY created_at DESC LIMIT 5",
            (sub['id'],), fetch='all') or []
    except Exception:
        tickets = []

    return render_template('cabinet/index.html',
        sub=sub, sim_cards=sim_cards, payments=payments,
        calls=calls, sms_list=sms_list, tickets=tickets)

@bp.route('/change_password', methods=['GET', 'POST'])
@login_required
@role_required('subscriber')
def change_password():
    if request.method == 'POST':
        old_pass = request.form.get('old_password', '')
        new_pass = request.form.get('new_password', '')
        confirm  = request.form.get('confirm_password', '')

        user = query("SELECT password_hash FROM tele3.users WHERE id=%s", (session['user_id'],), fetch='one')
        if not user or not check_password_hash(user['password_hash'], old_pass):
            flash('Неверный текущий пароль.', 'danger')
            return render_template('cabinet/change_password.html')
        if new_pass != confirm:
            flash('Новые пароли не совпадают.', 'warning')
            return render_template('cabinet/change_password.html')
        if len(new_pass) < 6:
            flash('Пароль должен быть не менее 6 символов.', 'warning')
            return render_template('cabinet/change_password.html')

        ph = generate_password_hash(new_pass)
        execute("UPDATE tele3.users SET password_hash=%s WHERE id=%s", (ph, session['user_id']))
        _log_security('change_password', 'Абонент сменил пароль')
        flash('Пароль успешно изменён.', 'success')
        return redirect(url_for('cabinet.index'))

    return render_template('cabinet/change_password.html')

@bp.route('/sims')
@login_required
@role_required('subscriber')
def my_sims():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id=%s ORDER BY phone_number",
                      (sub['id'],), fetch='all') or []
    tariffs = query("SELECT * FROM tele3.tariffs WHERE is_active=TRUE ORDER BY monthly_fee", fetch='all') or []
    return render_template('cabinet/sims.html', sub=sub, sim_cards=sim_cards, tariffs=tariffs)


@bp.route('/sims/<int:sim_id>/change_tariff', methods=['POST'])
@login_required
@role_required('subscriber')
def change_tariff(sim_id):
    sub = _get_subscriber()
    if not sub:
        flash('Профиль абонента не найден.', 'danger')
        return redirect(url_for('cabinet.index'))
    sim = query("SELECT id FROM tele3.v_sim_cards WHERE id=%s AND subscriber_id=%s", (sim_id, sub['id']), fetch='one')
    if not sim:
        flash('SIM-карта не найдена.', 'danger')
        return redirect(url_for('cabinet.my_sims'))
    tariff_id = request.form.get('tariff_id')
    if not tariff_id:
        flash('Выберите тариф.', 'warning')
        return redirect(url_for('cabinet.my_sims'))
    try:
        call_proc('tele3.sp_connect_tariff', (sim_id, int(tariff_id)))
        _log_security('change_tariff', f'sim_id={sim_id} tariff_id={tariff_id}')
        flash('Тариф успешно изменён.', 'success')
    except Exception as e:
        flash(f'Ошибка смены тарифа: {e}', 'danger')
    return redirect(url_for('cabinet.my_sims'))


@bp.route('/sims/<int:sim_id>/block', methods=['POST'])
@login_required
@role_required('subscriber')
def block_sim(sim_id):
    sub = _get_subscriber()
    if not sub:
        flash('Профиль не найден.', 'danger')
        return redirect(url_for('cabinet.index'))
    sim = query("SELECT id FROM tele3.v_sim_cards WHERE id=%s AND subscriber_id=%s", (sim_id, sub['id']), fetch='one')
    if not sim:
        flash('SIM-карта не найдена.', 'danger')
        return redirect(url_for('cabinet.my_sims'))
    action = request.form.get('action', 'blocked')
    try:
        call_proc('tele3.sp_set_sim_status', (sim_id, action))
        _log_security('sim_status_change', f'sim_id={sim_id} action={action}')
        flash(f'Статус SIM обновлён: {action}.', 'success')
    except Exception as e:
        flash(f'Ошибка: {e}', 'danger')
    return redirect(url_for('cabinet.my_sims'))

@bp.route('/services')
@login_required
@role_required('subscriber')
def my_services():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id=%s ORDER BY phone_number",
                      (sub['id'],), fetch='all') or []
    all_svcs = query("SELECT * FROM tele3.services WHERE is_active=TRUE ORDER BY name", fetch='all') or []
    connected = {}
    for s in sim_cards:
        try:
            connected[s['id']] = query(
                "SELECT * FROM tele3.v_connected_services WHERE sim_id=%s", (s['id'],), fetch='all') or []
        except Exception:
            connected[s['id']] = []
    return render_template('cabinet/services.html', sub=sub, sim_cards=sim_cards,
                           all_svcs=all_svcs, connected=connected)


@bp.route('/services/<int:sim_id>/toggle', methods=['POST'])
@login_required
@role_required('subscriber')
def toggle_service(sim_id):
    sub = _get_subscriber()
    if not sub:
        flash('Профиль не найден.', 'danger')
        return redirect(url_for('cabinet.index'))
    sim = query("SELECT id FROM tele3.v_sim_cards WHERE id=%s AND subscriber_id=%s", (sim_id, sub['id']), fetch='one')
    if not sim:
        flash('SIM-карта не найдена.', 'danger')
        return redirect(url_for('cabinet.my_services'))
    service_id = request.form.get('service_id')
    action = request.form.get('action', 'connect')
    if not service_id:
        flash('Услуга не выбрана.', 'warning')
        return redirect(url_for('cabinet.my_services'))
    try:
        call_proc('tele3.sp_toggle_service', (sim_id, int(service_id), action))
        _log_security('toggle_service', f'sim_id={sim_id} service_id={service_id} action={action}')
        flash('Услуга обновлена.', 'success')
    except Exception as e:
        flash(f'Ошибка: {e}', 'danger')
    return redirect(url_for('cabinet.my_services'))

@bp.route('/payments')
@login_required
@role_required('subscriber')
def my_payments():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    page     = max(1, int(request.args.get('page', 1)))
    per_page = 20
    offset   = (page - 1) * per_page
    try:
        payments = query(
            "SELECT * FROM tele3.v_payments WHERE subscriber_id=%s ORDER BY payment_date DESC LIMIT %s OFFSET %s",
            (sub['id'], per_page, offset), fetch='all') or []
        total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_payments WHERE subscriber_id=%s", (sub['id'],), fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        payments, total = [], 0
        flash(f'Ошибка загрузки платежей: {e}', 'danger')
    return render_template('cabinet/payments.html', sub=sub, payments=payments,
                           page=page, per_page=per_page, total=total)


@bp.route('/payments/pay', methods=['GET', 'POST'])
@login_required
@role_required('subscriber')
def make_payment():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    if request.method == 'POST':
        amount = request.form.get('amount', '0')
        method = request.form.get('payment_method', 'card')
        try:
            amount_f = float(amount)
            if amount_f <= 0:
                raise ValueError("Сумма должна быть > 0")
            call_proc('tele3.sp_add_payment', (sub['id'], amount_f, method, 'Оплата через личный кабинет'))
            _log_security('make_payment', f'amount={amount_f} method={method}')
            flash(f'Платёж на {amount_f} ₽ успешно зарегистрирован.', 'success')
            return redirect(url_for('cabinet.my_payments'))
        except Exception as e:
            flash(f'Ошибка при оплате: {e}', 'danger')
    return render_template('cabinet/make_payment.html', sub=sub)

@bp.route('/calls')
@login_required
@role_required('subscriber')
def my_calls():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id=%s ORDER BY phone_number",
                      (sub['id'],), fetch='all') or []
    sim_id = request.args.get('sim_id')
    if not sim_id and sim_cards:
        sim_id = sim_cards[0]['id']
    page = max(1, int(request.args.get('page', 1)))
    per_page = 30
    offset = (page - 1) * per_page
    calls, total = [], 0
    if sim_id:
        try:
            calls = query(
                "SELECT * FROM tele3.v_calls WHERE sim_id=%s ORDER BY call_datetime DESC LIMIT %s OFFSET %s",
                (sim_id, per_page, offset), fetch='all') or []
            t = query("SELECT COUNT(*) AS cnt FROM tele3.v_calls WHERE sim_id=%s", (sim_id,), fetch='one')
            total = t['cnt'] if t else 0
        except Exception:
            calls = []
    return render_template('cabinet/calls.html', sub=sub, sim_cards=sim_cards,
                           calls=calls, selected_sim=int(sim_id) if sim_id else None,
                           page=page, per_page=per_page, total=total)


@bp.route('/sms')
@login_required
@role_required('subscriber')
def my_sms():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    sim_cards = query("SELECT * FROM tele3.v_sim_cards WHERE subscriber_id=%s ORDER BY phone_number",
                      (sub['id'],), fetch='all') or []
    sim_id = request.args.get('sim_id')
    if not sim_id and sim_cards:
        sim_id = sim_cards[0]['id']
    page = max(1, int(request.args.get('page', 1)))
    per_page = 30
    offset = (page - 1) * per_page
    sms_list, total = [], 0
    if sim_id:
        try:
            sms_list = query(
                "SELECT * FROM tele3.v_sms WHERE sim_id=%s ORDER BY sent_datetime DESC LIMIT %s OFFSET %s",
                (sim_id, per_page, offset), fetch='all') or []
            t = query("SELECT COUNT(*) AS cnt FROM tele3.v_sms WHERE sim_id=%s", (sim_id,), fetch='one')
            total = t['cnt'] if t else 0
        except Exception:
            sms_list = []
    return render_template('cabinet/sms.html', sub=sub, sim_cards=sim_cards,
                           sms_list=sms_list, selected_sim=int(sim_id) if sim_id else None,
                           page=page, per_page=per_page, total=total)

@bp.route('/tickets')
@login_required
@role_required('subscriber')
def my_tickets():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    try:
        tickets = query(
            "SELECT * FROM tele3.tickets WHERE subscriber_id=%s ORDER BY created_at DESC",
            (sub['id'],), fetch='all') or []
    except Exception:
        tickets = []
    return render_template('cabinet/tickets.html', sub=sub, tickets=tickets)


@bp.route('/tickets/create', methods=['GET', 'POST'])
@login_required
@role_required('subscriber')
def create_ticket():
    sub = _get_subscriber()
    if not sub:
        return render_template('cabinet/no_subscriber.html')
    if request.method == 'POST':
        subject = request.form.get('subject', '').strip()
        body    = request.form.get('body', '').strip()
        if not subject or not body:
            flash('Заполните тему и текст обращения.', 'warning')
            return render_template('cabinet/ticket_form.html', sub=sub)
        try:
            execute(
                """INSERT INTO tele3.tickets(subscriber_id, subject, body, status, created_at)
                   VALUES (%s, %s, %s, 'open', NOW())""",
                (sub['id'], subject, body)
            )
            _log_security('create_ticket', f'subject={subject[:50]}')
            flash('Обращение отправлено. Мы свяжемся с вами в ближайшее время.', 'success')
            return redirect(url_for('cabinet.my_tickets'))
        except Exception as e:
            flash(f'Ошибка при создании обращения: {e}', 'danger')
    return render_template('cabinet/ticket_form.html', sub=sub)
