from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query, call_proc, execute
from app.auth import role_required, login_required
from app.routes.utils import get_page

bp = Blueprint('payments', __name__)


@bp.route('/')
@login_required
@role_required('admin', 'billing_operator', 'security_admin', 'support')
def index():
    page     = max(1, int(request.args.get('page', 1)))
    per_page = 25
    offset   = (page - 1) * per_page
    search   = request.args.get('q', '').strip()

    try:
        if search:
            rows = query(
                """SELECT * FROM tele3.v_payments
                   WHERE subscriber_name ILIKE %s ORDER BY payment_date DESC LIMIT %s OFFSET %s""",
                (f'%{search}%', per_page, offset), fetch='all') or []
            total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_payments WHERE subscriber_name ILIKE %s",
                              (f'%{search}%',), fetch='one')
        else:
            rows  = query("SELECT * FROM tele3.v_payments ORDER BY payment_date DESC LIMIT %s OFFSET %s",
                          (per_page, offset), fetch='all') or []
            total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_payments", fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        flash(f'Ошибка загрузки платежей: {e}', 'danger')
        rows, total = [], 0

    return render_template('payments/index.html',
        payments=rows, page=page, per_page=per_page, total=total, search=search)


@bp.route('/create', methods=['GET', 'POST'])
@login_required
@role_required('admin', 'billing_operator', 'security_admin')
def create():
    subscribers = query("SELECT id, last_name, first_name FROM tele3.subscribers ORDER BY last_name", fetch='all') or []
    if request.method == 'POST':
        f = request.form
        try:
            call_proc('tele3.sp_add_payment', (
                int(f['subscriber_id']),
                float(f['amount']),
                f.get('payment_method', 'cash'),
                f.get('notes', '') or None
            ))
            flash('Платёж зарегистрирован.', 'success')
            return redirect(url_for('payments.index'))
        except Exception as e:
            flash(f'Ошибка при добавлении платежа: {e}', 'danger')
    return render_template('payments/form.html', subscribers=subscribers)
