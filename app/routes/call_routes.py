"""call_routes.py"""
from flask import Blueprint, render_template, request
from app.db import query
from app.auth import role_required, login_required

bp = Blueprint('calls', __name__)

@bp.route('/')
@login_required
@role_required('admin', 'support', 'security_admin', 'billing_operator')
def index():
    page = max(1, int(request.args.get('page', 1)))
    per_page = 30
    offset = (page - 1) * per_page
    search = request.args.get('q', '').strip()
    try:
        if search:
            rows  = query("SELECT * FROM tele3.v_calls WHERE phone_number ILIKE %s ORDER BY call_datetime DESC LIMIT %s OFFSET %s",
                          (f'%{search}%', per_page, offset), fetch='all') or []
            total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_calls WHERE phone_number ILIKE %s", (f'%{search}%',), fetch='one')
        else:
            rows  = query("SELECT * FROM tele3.v_calls ORDER BY call_datetime DESC LIMIT %s OFFSET %s", (per_page, offset), fetch='all') or []
            total_row = query("SELECT COUNT(*) AS cnt FROM tele3.v_calls", fetch='one')
        total = total_row['cnt'] if total_row else 0
    except Exception as e:
        rows, total = [], 0
    return render_template('calls/index.html', calls=rows, page=page, per_page=per_page, total=total, search=search)
