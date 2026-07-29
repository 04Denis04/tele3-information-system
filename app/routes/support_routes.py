from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from app.db import query, execute
from app.auth import role_required, login_required
from app.routes.utils import get_page

bp = Blueprint('support', __name__)


@bp.route('/tickets')
@login_required
@role_required('admin', 'support', 'security_admin')
def tickets():
    status_f = request.args.get('status', '')
    page     = max(1, int(request.args.get('page', 1)))
    per_page = 25
    offset   = (page - 1) * per_page

    conds, params = [], []
    if status_f:
        conds.append("t.status = %s")
        params.append(status_f)

    where = ('WHERE ' + ' AND '.join(conds)) if conds else ''
    try:
        rows = query(
            f"""SELECT t.*, s.last_name || ' ' || s.first_name AS subscriber_name
                FROM tele3.tickets t
                JOIN tele3.subscribers s ON s.id = t.subscriber_id
                {where}
                ORDER BY t.created_at DESC LIMIT %s OFFSET %s""",
            params + [per_page, offset], fetch='all') or []
        total_row = query(
            f"""SELECT COUNT(*) AS cnt FROM tele3.tickets t {where}""",
            params, fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        flash(f'Ошибка загрузки обращений: {e}', 'danger')
        rows, total = [], 0

    return render_template('support/tickets.html',
        tickets=rows, status_f=status_f, page=page, per_page=per_page, total=total)


@bp.route('/tickets/<int:ticket_id>')
@login_required
@role_required('admin', 'support', 'security_admin')
def ticket_detail(ticket_id):
    try:
        ticket = query(
            """SELECT t.*, s.last_name || ' ' || s.first_name AS subscriber_name,
                      s.phone AS subscriber_phone, s.email AS subscriber_email
               FROM tele3.tickets t
               JOIN tele3.subscribers s ON s.id = t.subscriber_id
               WHERE t.id = %s""",
            (ticket_id,), fetch='one')
    except Exception as e:
        flash(f'Ошибка: {e}', 'danger')
        return redirect(url_for('support.tickets'))

    if not ticket:
        flash('Обращение не найдено.', 'danger')
        return redirect(url_for('support.tickets'))

    return render_template('support/ticket_detail.html', ticket=ticket)


@bp.route('/tickets/<int:ticket_id>/update', methods=['POST'])
@login_required
@role_required('admin', 'support')
def ticket_update(ticket_id):
    status  = request.form.get('status', 'open')
    comment = request.form.get('comment', '').strip()
    try:
        execute(
            """UPDATE tele3.tickets SET status=%s, resolved_at=CASE WHEN %s='closed' THEN NOW() ELSE resolved_at END,
               support_comment=%s, updated_at=NOW() WHERE id=%s""",
            (status, status, comment or None, ticket_id)
        )
        flash('Обращение обновлено.', 'success')
    except Exception as e:
        flash(f'Ошибка: {e}', 'danger')
    return redirect(url_for('support.ticket_detail', ticket_id=ticket_id))
