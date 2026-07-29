from flask import Blueprint, render_template, request, redirect, url_for, flash
from app.db import query, execute
from app.auth import role_required, login_required

bp = Blueprint('services', __name__)

@bp.route('/')
@login_required
def index():
    rows = query("SELECT * FROM tele3.services ORDER BY name", fetch='all')
    return render_template('services/index.html', services=rows)

@bp.route('/create', methods=['GET','POST'])
@login_required
@role_required('admin')
def create():
    if request.method == 'POST':
        f = request.form
        try:
            execute("INSERT INTO tele3.services(name,cost,description) VALUES(%s,%s,%s)",
                    (f['name'].strip(), float(f.get('cost',0)), f.get('description','').strip() or None))
            flash('Услуга добавлена.', 'success')
            return redirect(url_for('services.index'))
        except Exception:
            flash('Ошибка при добавлении услуги.', 'danger')
    return render_template('services/form.html', service=None)

@bp.route('/<int:sid>/edit', methods=['GET','POST'])
@login_required
@role_required('admin')
def edit(sid):
    service = query("SELECT * FROM tele3.services WHERE id=%s",(sid,),fetch='one')
    if not service:
        flash('Услуга не найдена.','danger')
        return redirect(url_for('services.index'))
    if request.method == 'POST':
        f = request.form
        try:
            execute("UPDATE tele3.services SET name=%s,cost=%s,description=%s WHERE id=%s",
                    (f['name'].strip(), float(f.get('cost',0)), f.get('description','') or None, sid))
            flash('Услуга обновлена.', 'success')
            return redirect(url_for('services.index'))
        except Exception:
            flash('Ошибка при обновлении.', 'danger')
    return render_template('services/form.html', service=service)
