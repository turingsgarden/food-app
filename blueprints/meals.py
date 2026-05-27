from __future__ import annotations

import base64
import json
import os
import traceback
import time
from datetime import datetime
from io import BytesIO

from bson import ObjectId
from flask import Blueprint, jsonify, request
from PIL import Image

from auth_utils import db_required, token_required
from extensions import analysis_collection, db, gemini_model, meals_collection
from model_pipeline import full_image_analysis, validate_image_for_analysis

meals_bp = Blueprint("meals", __name__)


def compress_base64_image(base64_str, quality=5):
    try:
        image_data = base64.b64decode(base64_str)
        image = Image.open(BytesIO(image_data)).convert("RGB")
        buffer = BytesIO()
        image.save(buffer, format="JPEG", quality=quality)
        return base64.b64encode(buffer.getvalue()).decode("utf-8")
    except Exception as e:
        print(f"❌ Compress: {e}")
        return None


def image_file_to_base64(image_path):
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


@meals_bp.route("/analyze", methods=["POST"])
@token_required
def analyze():
    try:
        if not gemini_model:
            return jsonify({"error": "AI service unavailable"}), 503
        if "image" not in request.files:
            return jsonify({"error": "No image in request"}), 400
        image_file = request.files["image"]
        user_id = request.user_id

        image_file.seek(0, 2)
        file_size = image_file.tell()
        image_file.seek(0)
        if file_size > 10 * 1024 * 1024:
            return jsonify({"error": "Image too large (max 10MB)"}), 413
        if file_size < 1024:
            return jsonify({"error": "Image too small"}), 400

        filename = f"image_{int(time.time() * 1000)}.png"
        image_path = os.path.join("/tmp", filename)
        image_file.save(image_path)

        is_valid, msg = validate_image_for_analysis(image_path)
        if not is_valid:
            try:
                os.remove(image_path)
            except Exception:
                pass
            return jsonify({"error": f"Invalid image: {msg}"}), 400

        from concurrent.futures import ThreadPoolExecutor
        import concurrent.futures

        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(full_image_analysis, image_path, user_id)
            try:
                result = future.result(timeout=90)
                if "error" in result:
                    try:
                        os.remove(image_path)
                    except Exception:
                        pass
                    return jsonify({"error": f"Analysis failed: {result.get('error')}"}), 500
                if result.get("dish_prediction", "").lower().startswith(
                    ("analysis failed", "could not identify", "unable to analyze")
                ):
                    try:
                        os.remove(image_path)
                    except Exception:
                        pass
                    return jsonify({"error": "Unable to analyze image"}), 422
            except concurrent.futures.TimeoutError:
                try:
                    os.remove(image_path)
                except Exception:
                    pass
                return jsonify({"error": "Analysis timeout"}), 408

        result["user_id"] = user_id
        nutrition_info = result.get("nutrition_info", "")
        image_base64 = image_thumb = None
        try:
            image_base64 = image_file_to_base64(image_path)
            image_thumb = compress_base64_image(image_base64)
        except Exception:
            pass
        try:
            if analysis_collection is not None:
                analysis_collection.insert_one(
                    {
                        "user_id": user_id,
                        "dish_prediction": result.get("dish_prediction", ""),
                        "image_description": result.get("image_description", ""),
                        "nutrition_info": nutrition_info,
                        "hidden_ingredients": result.get("hidden_ingredients", ""),
                        "image_full": image_base64,
                        "image_thumb": image_thumb,
                        "meal_type": result.get("meal_type", "Unknown"),
                        "analysis_method": "dynamic_ai",
                        "contains_hardcoded_values": False,
                        "analysis_time": result.get("analysis_time"),
                        "analyzed_at": datetime.now().isoformat(),
                    }
                )
        except Exception:
            pass
        try:
            os.remove(image_path)
        except Exception:
            pass
        return jsonify(result), 200
    except Exception as e:
        print(f"❌ analyze: {e}")
        traceback.print_exc()
        try:
            if "image_path" in locals():
                os.remove(image_path)
        except Exception:
            pass
        return jsonify({"error": "Analysis failed", "details": str(e)}), 500


@meals_bp.route("/save-meal", methods=["POST"])
@token_required
@db_required
def save_meal():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        missing = [k for k in ["dish_prediction", "image_description", "nutrition_info"] if k not in data]
        if missing:
            return jsonify({"error": f"Missing: {', '.join(missing)}"}), 400
        user_id = request.user_id
        image = data.get("image")
        image_full = data.get("image_full") or image
        image_thumb = data.get("image_thumb") or (compress_base64_image(image) if image else None)
        meal = {
            "user_id": user_id,
            "dish_prediction": data["dish_prediction"],
            "image_description": data["image_description"],
            "nutrition_info": data["nutrition_info"],
            "hidden_ingredients": data.get("hidden_ingredients", ""),
            "image_full": image_full,
            "image_thumb": image_thumb,
            "meal_type": data.get("meal_type", "Lunch"),
            "saved_at": data.get("saved_at", datetime.now().isoformat()),
            "analysis_method": "dynamic_ai",
            "contains_hardcoded_values": False,
        }
        if data.get("request_id"):
            meal["request_id"] = data["request_id"]
        result = meals_collection.insert_one(meal)
        return jsonify({"message": "Meal saved", "meal_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@meals_bp.route("/user-meals", methods=["GET"])
@token_required
@db_required
def get_user_meals():
    try:
        user_id = request.user_id
        try:
            query = {"$or": [{"user_id": user_id}, {"user_id": ObjectId(user_id)}]}
        except Exception:
            query = {"user_id": user_id}
        meals = list(meals_collection.find(query).sort("saved_at", -1))
        print(f"📊 Found {len(meals)} meals for user {user_id}")
        processed = []
        for meal in meals:
            meal["_id"] = str(meal["_id"])
            if "image" in meal and isinstance(meal["image"], bytes):
                meal["image_thumb"] = base64.b64encode(meal["image"]).decode("utf-8")
                meal["image_full"] = meal["image_thumb"]
                del meal["image"]
            meal.setdefault("dish_prediction", meal.get("dish", "Unknown Dish"))
            meal.setdefault("image_description", meal.get("visible_ingredients", ""))
            meal.setdefault("hidden_ingredients", "")
            meal.setdefault("nutrition_info", "")
            meal.setdefault("meal_type", "Lunch")
            if "timestamp" in meal:
                meal["saved_at"] = (
                    meal["timestamp"].isoformat() if hasattr(meal["timestamp"], "isoformat") else str(meal["timestamp"])
                )
            else:
                meal.setdefault("saved_at", "")
            for f in ["timestamp", "visible_ingredients", "image_filename", "dish"]:
                meal.pop(f, None)
            meal.setdefault("image_full", "")
            meal.setdefault("image_thumb", "")
            meal.setdefault("from_diet_plan", False)
            meal.setdefault("compliance_score", None)
            processed.append(meal)
        return jsonify(processed), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@meals_bp.route("/update-meal", methods=["PUT"])
@token_required
@db_required
def update_meal():
    try:
        data = request.get_json()
        meal_id = data.get("meal_id")
        if not meal_id:
            return jsonify({"error": "Missing meal_id"}), 400
        meal = meals_collection.find_one({"_id": ObjectId(meal_id)})
        if not meal or meal["user_id"] != request.user_id:
            return jsonify({"error": "Not found or unauthorized"}), 404
        update_data = {}
        for field in ["dish_prediction", "image_description", "hidden_ingredients", "nutrition_info", "meal_type"]:
            if field in data:
                update_data[field] = data[field]
        update_data["updated_at"] = datetime.now().isoformat()
        result = meals_collection.update_one({"_id": ObjectId(meal_id)}, {"$set": update_data})
        if result.modified_count > 0:
            return jsonify({"message": "Meal updated"}), 200
        return jsonify({"error": "No changes made"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@meals_bp.route("/delete-meal", methods=["DELETE"])
@token_required
@db_required
def delete_meal():
    try:
        data = request.get_json()
        meal_id = data.get("meal_id")
        if not meal_id:
            return jsonify({"error": "Missing meal_id"}), 400
        meal = meals_collection.find_one({"_id": ObjectId(meal_id)})
        if not meal or meal["user_id"] != request.user_id:
            return jsonify({"error": "Not found or unauthorized"}), 404
        result = meals_collection.delete_one({"_id": ObjectId(meal_id)})
        if result.deleted_count > 0:
            return jsonify({"message": "Meal deleted"}), 200
        return jsonify({"error": "Not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@meals_bp.route("/recalculate-nutrition", methods=["POST"])
@token_required
def recalculate_nutrition():
    try:
        if not gemini_model:
            return jsonify({"error": "AI unavailable"}), 503
        data = request.get_json()
        ingredients = data.get("ingredients", "")
        if not ingredients:
            return jsonify({"error": "No ingredients"}), 400
        from model_pipeline import recalculate_nutrition_enhanced

        nutrition_info = recalculate_nutrition_enhanced(ingredients)
        return (
            jsonify(
                {
                    "nutrition_info": nutrition_info,
                    "calculation_method": "dynamic_ai",
                    "contains_hardcoded_values": False,
                }
            ),
            200,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@meals_bp.route("/meal-insight", methods=["POST"])
@token_required
@db_required
def meal_insight():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        meal_id = data.get("meal_id", "")
        nutrition_info = data.get("nutrition_info", "")
        dish_name = data.get("dish_name", "this meal")
        ingredients = data.get("ingredients", "")
        if not nutrition_info:
            return jsonify({"error": "nutrition_info required"}), 400
        health_profile = db["health_profiles"].find_one({"user_id": request.user_id}) or {}
        health_report = db["health_reports"].find_one({"user_id": request.user_id}, sort=[("created_at", -1)]) or {}
        if not gemini_model:
            return jsonify({"error": "AI service unavailable"}), 503
        insight = _generate_meal_insight(
            dish_name=dish_name,
            nutrition_info=nutrition_info,
            ingredients=ingredients,
            health_profile=health_profile,
            health_report=health_report,
            gemini_model=gemini_model,
        )
        insight["meal_id"] = meal_id
        insight["generated_at"] = datetime.now().isoformat()
        if meal_id:
            try:
                meals_collection.update_one({"_id": ObjectId(meal_id)}, {"$set": {"ai_insight": insight}})
                print(f"✅ AI insight saved for meal {meal_id}")
            except Exception as e:
                print(f"⚠️ Could not persist insight: {e}")
        return jsonify(insight), 200
    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format"}), 500
    except Exception as e:
        print(f"❌ meal_insight: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


def _bmi_category(bmi: float) -> str:
    if bmi < 18.5:
        return "Underweight"
    if bmi < 25:
        return "Normal"
    if bmi < 30:
        return "Overweight"
    return "Obese"


def _generate_meal_insight(dish_name, nutrition_info, ingredients, health_profile, health_report, gemini_model):
    profile_ctx = ""
    if health_profile:
        bmi = health_profile.get("weight_kg", 0) / ((health_profile.get("height_cm", 170) / 100) ** 2)
        parts = [
            f"Age {health_profile.get('age', '?')}, {health_profile.get('sex', '?')}",
            f"BMI {bmi:.1f} ({_bmi_category(bmi)})",
        ]
        if health_profile.get("systolic_bp"):
            parts.append(f"BP {health_profile['systolic_bp']}/{health_profile.get('diastolic_bp','?')} mmHg")
        if health_profile.get("fasting_blood_sugar"):
            parts.append(f"Blood sugar {health_profile['fasting_blood_sugar']} mmol/L")
        if health_profile.get("total_cholesterol"):
            parts.append(f"Cholesterol {health_profile['total_cholesterol']} mmol/L")
        prefs = health_profile.get("dietary_preferences", [])
        if prefs:
            parts.append(f"Diet: {', '.join(prefs)}")
        profile_ctx = "; ".join(parts)

    goals_ctx = ""
    daily_cal = 0
    daily_prot = 0
    daily_sod = 0
    if health_report:
        goals = health_report.get("goals", [])
        daily_cal = health_report.get("daily_calories", 0)
        daily_prot = health_report.get("protein_g", 0)
        daily_sod = health_report.get("sodium_mg", 0)
        goals_ctx = (
            f"Daily targets: {daily_cal} kcal, {daily_prot}g protein, {daily_sod}mg sodium. "
            f"Health goals: {', '.join(goals) if goals else 'general wellness'}."
        )

    prompt = f"""You are NutriCam AI, a personal nutrition coach. Analyse this meal and return a JSON insight.
MEAL: {dish_name}
NUTRITION (pipe-separated): {nutrition_info}
INGREDIENTS: {ingredients if ingredients else "(not provided)"}
USER HEALTH CONTEXT: {profile_ctx if profile_ctx else "No profile available"}
USER GOALS & DAILY TARGETS: {goals_ctx if goals_ctx else "No targets set"}
Daily calorie target: {daily_cal or "unknown"} kcal | protein: {daily_prot or "unknown"} g | sodium: {daily_sod or "2000"} mg

Return ONLY valid JSON with EXACTLY this structure:
{{"macro_score":{{"rating":"<Balanced/High Sodium/High Fat/Low Protein/High Calorie/Good>","color":"<green/orange/red>","summary":"<1 sentence>"}},"highlights":[{{"ingredient":"<name>","badge":"<badge>","note":"<1 sentence>"}}],"warnings":[{{"nutrient":"<name>","value":"<value with unit>","note":"<1 sentence>"}}],"tip":"<1 sentence max 20 words>","nutrient_insights":{{"calories":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"protein":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"fat":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"carbs":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"fiber":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"sugar":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}},"sodium":{{"status":"<ok|high|low>","insight":"<1 sentence>","suggestion":"<1 sentence>"}}}}}}"""

    resp = gemini_model.generate_content(prompt)
    raw = resp.text.strip().replace("```json", "").replace("```", "").strip()
    start = raw.find("{")
    end = raw.rfind("}") + 1
    if start >= 0 and end > start:
        raw = raw[start:end]
    result = json.loads(raw)
    result.setdefault("macro_score", {"rating": "N/A", "color": "gray", "summary": ""})
    result.setdefault("highlights", [])
    result.setdefault("warnings", [])
    result.setdefault("tip", "")
    default_ni = {"status": "ok", "insight": "", "suggestion": ""}
    ni = result.setdefault("nutrient_insights", {})
    for key in ["calories", "protein", "fat", "carbs", "fiber", "sugar", "sodium"]:
        if key not in ni or not isinstance(ni.get(key), dict):
            ni[key] = dict(default_ni)
        else:
            for subk, subv in default_ni.items():
                ni[key].setdefault(subk, subv)
    return result

