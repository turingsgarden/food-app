from __future__ import annotations

from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request

from auth_utils import db_required, token_required
from extensions import db, meals_collection, profiles_collection

profile_bp = Blueprint("profile", __name__)


@profile_bp.route("/save-profile", methods=["POST"])
@token_required
@db_required
def save_profile():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        profile_data = {k: v for k, v in data.items() if k != "user_id"}
        profile_data["updated_at"] = datetime.now().isoformat()
        profiles_collection.update_one({"user_id": request.user_id}, {"$set": profile_data}, upsert=True)
        return jsonify({"message": "Profile saved"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@profile_bp.route("/get-profile", methods=["GET"])
@token_required
@db_required
def get_profile():
    try:
        profile = profiles_collection.find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Profile not found"}), 404
        profile["_id"] = str(profile["_id"])
        return jsonify(profile), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── Dashboard Stats & Insights ──


@profile_bp.route("/dashboard-stats", methods=["GET"])
@token_required
@db_required
def get_dashboard_stats():
    try:
        now = datetime.now()
        today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        week_start = today - timedelta(days=today.weekday())
        month_start = today.replace(day=1)
        meals = list(meals_collection.find({"user_id": request.user_id}))

        def parse_dt(s):
            try:
                return datetime.fromisoformat(s.replace("Z", "+00:00"))
            except Exception:
                return datetime.min

        today_meals = [m for m in meals if parse_dt(m.get("saved_at", "")).date() == today.date()]
        week_meals = [m for m in meals if parse_dt(m.get("saved_at", "")) >= week_start]
        month_meals = [m for m in meals if parse_dt(m.get("saved_at", "")) >= month_start]
        water_entries = list(db["water"].find({"user_id": request.user_id}))
        today_water = sum(w["amount"] for w in water_entries if parse_dt(w.get("recorded_at", "")).date() == today.date())
        week_water = sum(w["amount"] for w in water_entries if parse_dt(w.get("recorded_at", "")) >= week_start)
        exercise_entries = list(db["exercise"].find({"user_id": request.user_id}))
        today_exercise = sum(
            e["duration"] for e in exercise_entries if parse_dt(e.get("recorded_at", "")).date() == today.date()
        )
        week_exercise = sum(e["duration"] for e in exercise_entries if parse_dt(e.get("recorded_at", "")) >= week_start)
        weight_entries = list(db["weight"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        current_weight = weight_entries[0]["weight"] if weight_entries else 0
        streak = 0
        check_date = today
        for _ in range(30):
            if any(parse_dt(m.get("saved_at", "")).date() == check_date.date() for m in meals):
                streak += 1
                check_date -= timedelta(days=1)
            else:
                break
        return (
            jsonify(
                {
                    "today": {"meals": len(today_meals), "water": today_water, "exercise": today_exercise},
                    "week": {"meals": len(week_meals), "water": week_water, "exercise": week_exercise},
                    "month": {"meals": len(month_meals)},
                    "current_weight": current_weight,
                    "streak": streak,
                    "timestamp": now.isoformat(),
                }
            ),
            200,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@profile_bp.route("/user-insights", methods=["GET"])
@token_required
@db_required
def get_user_insights():
    try:
        profile = profiles_collection.find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Profile not found"}), 404
        calorie_target = profile.get("calorie_target", 2000)
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        today_meals = list(meals_collection.find({"user_id": request.user_id, "saved_at": {"$gte": today.isoformat()}}))
        today_calories = 0
        for meal in today_meals:
            for line in meal.get("nutrition_info", "").split("\n"):
                if "calories" in line.lower():
                    parts = line.split("|")
                    if len(parts) >= 2:
                        try:
                            today_calories += int(parts[1].strip())
                        except Exception:
                            pass
        today_water = sum(
            w["amount"] for w in db["water"].find({"user_id": request.user_id, "recorded_at": {"$gte": today.isoformat()}})
        )
        today_exercise = sum(
            e["duration"]
            for e in db["exercise"].find({"user_id": request.user_id, "recorded_at": {"$gte": today.isoformat()}})
        )
        insights = []
        if today_calories > calorie_target * 1.2:
            insights.append(
                {
                    "type": "warning",
                    "title": "High Calorie Intake",
                    "message": f"You've consumed {today_calories} kcal, above your {calorie_target} goal.",
                    "icon": "exclamationmark.triangle.fill",
                    "color": "red",
                }
            )
        elif today_calories < calorie_target * 0.8:
            insights.append(
                {
                    "type": "info",
                    "title": "Low Calorie Intake",
                    "message": f"Only {today_calories} kcal today. Make sure you're eating enough!",
                    "icon": "info.circle.fill",
                    "color": "blue",
                }
            )
        if today_water < 1000:
            insights.append(
                {
                    "type": "reminder",
                    "title": "Stay Hydrated",
                    "message": f"Only {int(today_water)}ml today. Try to drink more!",
                    "icon": "drop.fill",
                    "color": "blue",
                }
            )
        if today_exercise == 0:
            insights.append(
                {
                    "type": "motivation",
                    "title": "Get Moving",
                    "message": "No exercise logged today. Even a short walk counts!",
                    "icon": "figure.walk",
                    "color": "green",
                }
            )
        return (
            jsonify(
                {
                    "insights": insights,
                    "today_stats": {"calories": today_calories, "water": today_water, "exercise": today_exercise},
                    "goals": {"calories": calorie_target, "water": 2000, "exercise": 30},
                }
            ),
            200,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500

