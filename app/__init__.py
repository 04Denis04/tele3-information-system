from flask import Flask, render_template, session
from config import Config
from app import db as db_module


def create_app():
    app = Flask(__name__, template_folder='templates', static_folder='static')
    app.config.from_object(Config)
    db_module.init_app(app)
    from app.routes.auth_routes       import bp as auth_bp
    from app.routes.admin_routes      import bp as admin_bp
    from app.routes.subscriber_routes import bp as sub_bp
    from app.routes.sim_routes        import bp as sim_bp
    from app.routes.tariff_routes     import bp as tariff_bp
    from app.routes.payment_routes    import bp as payment_bp
    from app.routes.call_routes       import bp as call_bp
    from app.routes.sms_routes        import bp as sms_bp
    from app.routes.service_routes    import bp as service_bp
    from app.routes.cabinet_routes    import bp as cabinet_bp
    from app.routes.support_routes    import bp as support_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(admin_bp,   url_prefix='/admin')
    app.register_blueprint(sub_bp,     url_prefix='/subscribers')
    app.register_blueprint(sim_bp,     url_prefix='/sim')
    app.register_blueprint(tariff_bp,  url_prefix='/tariffs')
    app.register_blueprint(payment_bp, url_prefix='/payments')
    app.register_blueprint(call_bp,    url_prefix='/calls')
    app.register_blueprint(sms_bp,     url_prefix='/sms')
    app.register_blueprint(service_bp, url_prefix='/services')
    app.register_blueprint(cabinet_bp, url_prefix='/cabinet')
    app.register_blueprint(support_bp, url_prefix='/support')
    @app.context_processor
    def inject_user():
        return {
            'current_user': {
                'id':       session.get('user_id'),
                'username': session.get('username'),
                'role':     session.get('role'),
                'fullname': session.get('fullname'),
            }
        }
    @app.errorhandler(403)
    def forbidden(e):
        return render_template('errors/403.html'), 403

    @app.errorhandler(404)
    def not_found(e):
        return render_template('errors/404.html'), 404

    @app.errorhandler(500)
    def server_error(e):
        role = session.get('role', '')
        show_detail = role in ('security_admin', 'admin')
        return render_template('errors/500.html', detail=str(e) if show_detail else None), 500

    return app
