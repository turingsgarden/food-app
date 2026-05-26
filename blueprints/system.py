from __future__ import annotations

import os
from datetime import datetime

from flask import Blueprint, jsonify

from execution_trace import get_trace_steps
from extensions import client

system_bp = Blueprint("system", __name__)


@system_bp.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok", "timestamp": datetime.now().isoformat()}), 200


@system_bp.route("/")
def home():
    return {"message": "Food Analyzer Backend is Running", "version": "3.0"}, 200


@system_bp.route("/health", methods=["GET"])
def health():
    try:
        mongodb_status = "disconnected"
        if client:
            try:
                client.admin.command("ping")
                mongodb_status = "connected"
            except Exception:
                mongodb_status = "connection_failed"
        gemini_ok = bool(os.getenv("GEMINI_API_KEY"))
        return (
            jsonify(
                {
                    "status": "healthy" if mongodb_status == "connected" else "degraded",
                    "mongodb": mongodb_status,
                    "gemini": "configured" if gemini_ok else "missing",
                    "timestamp": datetime.now().isoformat(),
                }
            ),
            200 if mongodb_status == "connected" else 503,
        )
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503


@system_bp.route("/debug-env", methods=["GET"])
def debug_env():
    return (
        jsonify(
            {
                "has_mongo_uri": bool(os.getenv("MONGO_URI")),
                "has_gemini_key": bool(os.getenv("GEMINI_API_KEY")),
                "environment": os.getenv("ENVIRONMENT", "not-set"),
                "mongo_db": os.getenv("MONGO_DB", "not-set"),
                "jwt_secret_set": bool(os.getenv("JWT_SECRET_KEY")),
                "has_langfuse_key": bool(os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY")),
            }
        ),
        200,
    )


@system_bp.route("/trace/<request_id>", methods=["GET"])
def trace(request_id: str):
    steps = get_trace_steps(request_id)
    if not steps:
        return jsonify({"error": "Trace not found"}), 404
    return jsonify({"request_id": request_id, "steps": steps}), 200

