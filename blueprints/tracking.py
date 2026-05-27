from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request

from auth_utils import db_required, token_required
from extensions import db

tracking_bp = Blueprint("tracking", __name__)


@tracking_bp.route("/add-exercise", methods=["POST"])
@token_required
@db_required
def add_exercise():
    try:
        data = request.get_json()
        missing = [k for k in ["exercise_type", "duration"] if k not in data]
        if missing:
            return jsonify({"error": f"Missing: {', '.join(missing)}"}), 400
        col = db["exercise"]
        col.create_index([("user_id", 1), ("recorded_at", -1)])
        result = col.insert_one(
            {
                "user_id": request.user_id,
                "exercise_type": data["exercise_type"],
                "duration": data["duration"],
                "intensity": data.get("intensity", "Moderate"),
                "calories_burned": data.get("calories_burned", 0),
                "notes": data.get("notes", ""),
                "recorded_at": data.get("recorded_at", datetime.now().isoformat()),
            }
        )
        return jsonify({"message": "Exercise added", "exercise_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@tracking_bp.route("/user-exercise", methods=["GET"])
@token_required
@db_required
def get_user_exercise():
    try:
        entries = list(db["exercise"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries:
            e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@tracking_bp.route("/add-water", methods=["POST"])
@token_required
@db_required
def add_water():
    try:
        data = request.get_json()
        if not data.get("amount"):
            return jsonify({"error": "Missing amount"}), 400
        col = db["water"]
        col.create_index([("user_id", 1), ("recorded_at", -1)])
        result = col.insert_one(
            {
                "user_id": request.user_id,
                "amount": data["amount"],
                "recorded_at": data.get("recorded_at", datetime.now().isoformat()),
            }
        )
        return jsonify({"message": "Water added", "water_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@tracking_bp.route("/user-water", methods=["GET"])
@token_required
@db_required
def get_user_water():
    try:
        entries = list(db["water"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries:
            e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@tracking_bp.route("/add-weight", methods=["POST"])
@token_required
@db_required
def add_weight():
    try:
        data = request.get_json()
        if not data.get("weight"):
            return jsonify({"error": "Missing weight"}), 400
        col = db["weight"]
        col.create_index([("user_id", 1), ("recorded_at", -1)])
        result = col.insert_one(
            {
                "user_id": request.user_id,
                "weight": data["weight"],
                "recorded_at": data.get("recorded_at", datetime.now().isoformat()),
            }
        )
        return jsonify({"message": "Weight added", "weight_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@tracking_bp.route("/user-weight", methods=["GET"])
@token_required
@db_required
def get_user_weight():
    try:
        entries = list(db["weight"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries:
            e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

