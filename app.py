from __future__ import annotations

import os
import threading
import time

import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, redirect, request
from flask_cors import CORS

from extensions import client, gemini_model, init_extensions

load_dotenv()


def _keep_alive_loop():
    time.sleep(60)
    while True:
        try:
            requests.get("https://food-app-swift-qb4k.onrender.com/ping", timeout=10)
            print("🔄 Keep-alive ping sent")
        except Exception as e:
            print(f"⚠️ Keep-alive ping failed: {e}")
        time.sleep(25 * 60)


threading.Thread(target=_keep_alive_loop, daemon=True).start()
print("✅ Keep-alive thread started")


def create_app() -> Flask:
    init_extensions()

    app = Flask(__name__)
    app.config["SECRET_KEY"] = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-this")
    app.config["JWT_EXPIRATION_HOURS"] = 24 * 7
    CORS(app, supports_credentials=True)

    @app.before_request
    def force_https():
        if os.getenv("ENVIRONMENT", "development") == "production":
            if not request.is_secure and request.headers.get("X-Forwarded-Proto") != "https":
                return redirect(request.url.replace("http://", "https://"))

    from blueprints.auth import auth_bp
    from blueprints.health import health_bp
    from blueprints.meals import meals_bp
    from blueprints.profile import profile_bp
    from blueprints.system import system_bp
    from blueprints.tracking import tracking_bp

    app.register_blueprint(system_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(profile_bp)
    app.register_blueprint(meals_bp)
    app.register_blueprint(health_bp)
    app.register_blueprint(tracking_bp)

    @app.errorhandler(404)
    def not_found(error):
        return jsonify({"error": "Endpoint not found"}), 404

    @app.errorhandler(500)
    def internal_error(error):
        return jsonify({"error": "Internal server error"}), 500

    @app.errorhandler(413)
    def payload_too_large(error):
        return jsonify({"error": "Request payload too large"}), 413

    return app


app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"🚀 Starting on port {port}")
    print(f"🗄️ MongoDB: {'✅ Connected' if client else '❌ Not connected'}")
    print(f"🤖 Gemini AI: {'✅ Ready' if gemini_model else '❌ Not configured'}")
    app.run(host="0.0.0.0", port=port, threaded=True)
