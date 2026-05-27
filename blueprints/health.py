from __future__ import annotations

import json
import os
import re
import threading
import traceback
from datetime import datetime, timedelta
from io import BytesIO

import requests
from flask import Blueprint, jsonify, request

from auth_utils import db_required, token_required
from extensions import db, gemini_model, meal_plan_jobs, meals_collection
from health_pipeline import (
    analyze_meal_photo,
    generate_health_report,
    generate_nutrition_targets,
    generate_weekly_meal_plan,
)
from daily_banner import build_daily_banner_message

health_bp = Blueprint("health", __name__)


def _fetch_user_meal_history(user_id: str, days: int = 90, limit: int = 200) -> list:
    return list(
        db["meals"]
        .find(
            {
                "user_id": user_id,
                "saved_at": {"$gte": (datetime.now() - timedelta(days=days)).isoformat()},
            },
            {
                "dish_prediction": 1,
                "image_description": 1,
                "nutrition_info": 1,
                "hidden_ingredients": 1,
                "meal_type": 1,
                "saved_at": 1,
                "_id": 0,
            },
        )
        .sort("saved_at", -1)
        .limit(limit)
    )


@health_bp.route("/save-health-profile", methods=["POST"])
@token_required
@db_required
def save_health_profile():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        data["user_id"] = request.user_id
        data["updated_at"] = datetime.now().isoformat()
        db["health_profiles"].update_one({"user_id": request.user_id}, {"$set": data}, upsert=True)
        db["health_reports"].delete_many({"user_id": request.user_id})
        print(f"✅ Health profile saved for {request.user_id}")
        return jsonify({"success": True}), 200
    except Exception as e:
        print(f"❌ save_health_profile: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/get-health-profile", methods=["GET"])
@token_required
@db_required
def get_health_profile():
    try:
        profile = db["health_profiles"].find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "not found"}), 404
        profile["_id"] = str(profile["_id"])
        return jsonify(profile), 200
    except Exception as e:
        print(f"❌ get_health_profile: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/daily-banner-message", methods=["GET"])
@token_required
@db_required
def daily_banner_message():
    try:
        profile = db["health_profiles"].find_one({"user_id": request.user_id})
        if profile:
            profile.pop("_id", None)
        message = build_daily_banner_message(profile, meals_collection, request.user_id)
        return jsonify({"message": message, "generated_at": datetime.now().isoformat()}), 200
    except Exception as e:
        print(f"❌ daily_banner_message: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/generate-targets", methods=["POST"])
@token_required
@db_required
def generate_targets():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        result = generate_nutrition_targets(
            profile=data.get("profile", {}),
            goals=data.get("goals", []),
            gemini_model=gemini_model,
        )
        result["user_id"] = request.user_id
        result["goals"] = data.get("goals", [])
        result["created_at"] = datetime.now().isoformat()
        db["nutrition_plans"].update_one({"user_id": request.user_id}, {"$set": result}, upsert=True)
        return jsonify(result), 200
    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format, please try again"}), 500
    except Exception as e:
        print(f"❌ generate_targets: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@health_bp.route("/generate-meal-plan", methods=["POST"])
@token_required
@db_required
def generate_meal_plan_route():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        meal_history = _fetch_user_meal_history(request.user_id)
        print(f"📊 Loaded {len(meal_history)} meals for meal plan generation")
        result = generate_weekly_meal_plan(
            nutrition_plan=data.get("nutrition_plan", {}),
            health_profile=data.get("health_profile", {}),
            gemini_model=gemini_model,
            meal_history=meal_history,
        )
        result["user_id"] = request.user_id
        result["created_at"] = datetime.now().isoformat()
        db["meal_plans"].update_one({"user_id": request.user_id}, {"$set": result}, upsert=True)
        return jsonify(result), 200
    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format, please try again"}), 500
    except Exception as e:
        print(f"❌ generate_meal_plan: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@health_bp.route("/generate-meal-plan-async", methods=["POST"])
@token_required
@db_required
def generate_meal_plan_async():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        job_id = f"{request.user_id}_{int(datetime.now().timestamp() * 1000)}"
        meal_plan_jobs[job_id] = {"status": "generating", "result": None, "error": None}
        user_id = request.user_id

        def run_generation():
            try:
                print(f"🍽️ Background job {job_id} started")
                meal_history = _fetch_user_meal_history(user_id)
                print(f"📊 Loaded {len(meal_history)} meals for async meal plan")
                result = generate_weekly_meal_plan(
                    nutrition_plan=data.get("nutrition_plan", {}),
                    health_profile=data.get("health_profile", {}),
                    days=data.get("days", 7),
                    meals_per_day=data.get("meals_per_day", 3),
                    gemini_model=gemini_model,
                    meal_history=meal_history,
                )
                result["user_id"] = user_id
                result["created_at"] = datetime.now().isoformat()
                db["meal_plans"].update_one({"user_id": user_id}, {"$set": result}, upsert=True)
                meal_plan_jobs[job_id] = {"status": "done", "result": result, "error": None}
                print(f"✅ Background job {job_id} complete")
            except Exception as e:
                print(f"❌ Background job {job_id} failed: {e}")
                traceback.print_exc()
                meal_plan_jobs[job_id] = {"status": "error", "result": None, "error": str(e)}

        threading.Thread(target=run_generation, daemon=True).start()
        return jsonify({"job_id": job_id, "status": "generating"}), 202
    except Exception as e:
        print(f"❌ generate_meal_plan_async: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/meal-plan-status/<job_id>", methods=["GET"])
@token_required
def meal_plan_status(job_id):
    job = meal_plan_jobs.get(job_id)
    if not job:
        return jsonify({"status": "error", "error": "Job not found, please generate again"}), 404
    return jsonify(job), 200


@health_bp.route("/get-meal-plan", methods=["GET"])
@token_required
@db_required
def get_meal_plan():
    try:
        plan = db["meal_plans"].find_one({"user_id": request.user_id}, sort=[("created_at", -1)])
        if not plan:
            return jsonify({"error": "not found"}), 404
        plan["_id"] = str(plan["_id"])
        return jsonify(plan), 200
    except Exception as e:
        print(f"❌ get_meal_plan: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/analyze-meal-photo", methods=["POST"])
@token_required
@db_required
def analyze_meal_photo_route():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        image_b64 = data.get("image_base64", "")
        if not image_b64:
            return jsonify({"error": "No image provided"}), 400

        user_id = request.user_id
        meal_type = data.get("meal_type", "lunch")
        date_str = data.get("date", datetime.now().strftime("%Y-%m-%d"))

        result = analyze_meal_photo(
            image_b64=image_b64,
            meal_type=meal_type,
            planned_meal=data.get("planned_meal", {}),
            remaining_plan=data.get("remaining_plan", []),
            gemini_model=gemini_model,
            user_id=user_id,
        )

        log_doc = {
            "user_id": user_id,
            "date": date_str,
            "meal_type": meal_type,
            "planned_meal": data.get("planned_meal", {}),
            "detected_foods": result.get("detected_foods", []),
            "estimated_calories": result.get("estimated_calories", 0),
            "estimated_protein": result.get("estimated_protein", 0),
            "estimated_carbs": result.get("estimated_carbs", 0),
            "estimated_fat": result.get("estimated_fat", 0),
            "compliance_score": result.get("compliance_score", 0),
            "compliance_feedback": result.get("compliance_feedback", ""),
            "plan_adjustment_note": result.get("plan_adjustment_note"),
            "saved_at": datetime.now().isoformat(),
        }
        db["meal_logs"].insert_one(log_doc)

        estimated_cal = result.get("estimated_calories", 0)
        nutrition_info = result.get("nutrition_info", "")
        if not nutrition_info:
            ep = result.get("estimated_protein", 0)
            ec = result.get("estimated_carbs", 0)
            ef = result.get("estimated_fat", 0)
            nutrition_info = (
                f"Calories|{estimated_cal}|kcal\nProtein|{ep}|g\n"
                f"Fat|{ef}|g\nCarbohydrates|{ec}|g\n"
                f"Fiber|0|g\nSugar|0|g\nSodium|0|mg"
            )

        dish = result.get("dish_prediction") or f"Diet Plan {meal_type.capitalize()}"
        img_desc = result.get("image_description") or ", ".join(result.get("detected_foods", []))

        try:
            import base64 as b64mod
            from PIL import Image as PILImage

            raw = b64mod.b64decode(image_b64)
            img = PILImage.open(BytesIO(raw)).convert("RGB")
            buf = BytesIO()
            img.thumbnail((200, 200))
            img.save(buf, format="JPEG", quality=50)
            thumb_b64 = b64mod.b64encode(buf.getvalue()).decode()
        except Exception as ie:
            print(f"⚠️ Thumb failed: {ie}")
            thumb_b64 = None

        meal_doc = {
            "user_id": user_id,
            "dish_prediction": dish,
            "image_description": img_desc,
            "nutrition_info": nutrition_info,
            "hidden_ingredients": result.get("hidden_ingredients", ""),
            "image_full": None,
            "image_thumb": thumb_b64,
            "meal_type": meal_type.capitalize(),
            "saved_at": datetime.now().isoformat(),
            "analysis_method": "health_agent",
            "from_diet_plan": True,
            "compliance_score": result.get("compliance_score", 0),
        }
        meals_collection.insert_one(meal_doc)
        print(f"✅ Meal saved: {dish} | {estimated_cal} kcal")

        return jsonify(result), 200

    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format"}), 500
    except Exception as e:
        print(f"❌ analyze_meal_photo_route: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@health_bp.route("/generate-health-report", methods=["POST"])
@token_required
@db_required
def generate_health_report_route():
    try:
        data = request.get_json()
        force_regenerate = data.get("force", False) if data else False

        if not force_regenerate:
            existing = db["health_reports"].find_one({"user_id": request.user_id}, sort=[("created_at", -1)])
            if existing:
                cache_valid = False
                cache_age_days = None
                try:
                    created_at = datetime.fromisoformat(existing.get("created_at", ""))
                    cache_age_days = (datetime.now() - created_at).days
                    cache_valid = cache_age_days < 7
                except Exception:
                    pass

                if cache_valid:
                    existing["_id"] = str(existing["_id"])
                    print(f"📋 Returning cached health report for {request.user_id} (age: {cache_age_days}d)")
                    return jsonify(existing), 200
                print(f"♻️ Cache expired ({cache_age_days}d), regenerating report")

        profile = db["health_profiles"].find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Health profile not found"}), 404
        profile.pop("_id", None)

        goals = data.get("goals", []) if data else []
        if not goals:
            plan = db["nutrition_plans"].find_one({"user_id": request.user_id})
            if plan:
                goals = plan.get("goals", [])

        meal_history = _fetch_user_meal_history(request.user_id)

        print(f"📊 Loaded {len(meal_history)} meals for health report analysis")

        result = generate_health_report(
            profile=profile,
            goals=goals,
            gemini_model=gemini_model,
            meal_history=meal_history,
        )

        result["user_id"] = request.user_id
        result["goals"] = goals
        result["created_at"] = datetime.now().isoformat()

        db["health_reports"].update_one({"user_id": request.user_id}, {"$set": result}, upsert=True)

        db["nutrition_plans"].update_one(
            {"user_id": request.user_id},
            {
                "$set": {
                    "user_id": request.user_id,
                    "daily_calories": result.get("daily_calories", 2000),
                    "protein_g": result.get("protein_g", 100),
                    "carbs_g": result.get("carbs_g", 250),
                    "fat_g": result.get("fat_g", 65),
                    "fiber_g": result.get("fiber_g", 25),
                    "sodium_mg": result.get("sodium_mg", 2300),
                    "goals": goals,
                    "updated_at": datetime.now().isoformat(),
                }
            },
            upsert=True,
        )

        print(
            f"✅ Health report generated | score={result.get('health_score')} "
            f"| {result.get('daily_calories')} kcal/day "
            f"| foods={len(result.get('recommended_foods', []))}"
        )
        return jsonify(result), 200

    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format, please try again"}), 500
    except Exception as e:
        print(f"❌ generate_health_report_route: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@health_bp.route("/get-health-report", methods=["GET"])
@token_required
@db_required
def get_health_report():
    try:
        report = db["health_reports"].find_one({"user_id": request.user_id}, sort=[("created_at", -1)])
        if not report:
            return jsonify({"error": "not found"}), 404
        report["_id"] = str(report["_id"])
        return jsonify(report), 200
    except Exception as e:
        print(f"❌ get_health_report: {e}")
        return jsonify({"error": str(e)}), 500


@health_bp.route("/ocr-health-report", methods=["POST"])
@token_required
def ocr_health_report():
    try:
        data = request.get_json()
        if not data or not data.get("image_base64"):
            return jsonify({"error": "No image provided"}), 400

        image_b64 = data["image_base64"]
        vision_key = os.getenv("GOOGLE_VISION_API_KEY")
        if not vision_key:
            return jsonify({"error": "OCR service not configured on server"}), 503

        vision_url = f"https://vision.googleapis.com/v1/images:annotate?key={vision_key}"
        vision_payload = {
            "requests": [
                {
                    "image": {"content": image_b64},
                    "features": [{"type": "DOCUMENT_TEXT_DETECTION", "maxResults": 1}],
                    "imageContext": {"languageHints": ["en", "zh-Hans", "zh-Hant"]},
                }
            ]
        }

        print("📤 Calling Google Vision API...")
        vision_resp = requests.post(
            vision_url,
            json=vision_payload,
            headers={"Content-Type": "application/json"},
            timeout=20,
        )

        if vision_resp.status_code != 200:
            err_body = vision_resp.text[:300]
            print(f"❌ Google Vision API {vision_resp.status_code}: {err_body}")
            return jsonify({"error": f"OCR service error ({vision_resp.status_code})."}), 502

        vision_data = vision_resp.json()
        if "error" in vision_data.get("responses", [{}])[0]:
            api_err = vision_data["responses"][0]["error"]
            return jsonify({"error": api_err.get("message", "OCR failed")}), 502

        try:
            full_text = vision_data["responses"][0]["fullTextAnnotation"]["text"]
        except (KeyError, IndexError):
            try:
                annotations = vision_data["responses"][0].get("textAnnotations", [])
                full_text = annotations[0].get("description", "") if annotations else ""
            except (KeyError, IndexError):
                full_text = ""

        if not full_text.strip():
            return (
                jsonify(
                    {
                        "systolic_bp": None,
                        "diastolic_bp": None,
                        "blood_sugar": None,
                        "cholesterol": None,
                        "triglycerides": None,
                        "height_cm": None,
                        "weight_kg": None,
                        "message": "No text detected. Make sure the image is clear and well-lit.",
                    }
                ),
                200,
            )

        print(f"📄 Vision OCR extracted {len(full_text)} chars")

        if not gemini_model:
            return jsonify(_extract_health_values_regex(full_text)), 200

        extract_prompt = f"""You are a medical data extraction assistant.
Extract health values from this OCR text. Return ONLY valid JSON, no markdown:
{{"systolic_bp": <int or null>, "diastolic_bp": <int or null>, "blood_sugar": <float mmol/L or null>, "cholesterol": <float mmol/L or null>, "triglycerides": <float mmol/L or null>, "height_cm": <float or null>, "weight_kg": <float or null>}}

Rules: only extract clearly readable values. Use null if missing or ambiguous.
If mg/dL: glucose÷18, cholesterol÷38.67, triglycerides÷88.57.

OCR TEXT:
\"\"\"{full_text}\"\"\"
"""
        gemini_resp = gemini_model.generate_content(extract_prompt)
        raw = gemini_resp.text.strip().replace("```json", "").replace("```", "").strip()
        start = raw.find("{")
        end = raw.rfind("}") + 1
        if start >= 0 and end > start:
            raw = raw[start:end]
        else:
            return jsonify(_extract_health_values_regex(full_text)), 200

        result_json = json.loads(raw)
        cleaned = _validate_health_values(result_json)
        print(f"✅ OCR final: {cleaned}")
        return jsonify(cleaned), 200

    except json.JSONDecodeError:
        return jsonify({"error": "Could not parse scan results. Try a clearer image."}), 422
    except requests.exceptions.Timeout:
        return jsonify({"error": "OCR timed out. Please try again."}), 504
    except requests.exceptions.ConnectionError:
        return jsonify({"error": "Cannot reach OCR service. Check your connection."}), 503
    except Exception as e:
        print(f"❌ OCR unexpected error: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


def _validate_health_values(raw: dict) -> dict:
    def safe_int(val, lo, hi):
        if val is None:
            return None
        try:
            v = int(round(float(val)))
            return v if lo <= v <= hi else None
        except Exception:
            return None

    def safe_float(val, lo, hi, dp=1):
        if val is None:
            return None
        try:
            v = round(float(val), dp)
            return v if lo <= v <= hi else None
        except Exception:
            return None

    return {
        "systolic_bp": safe_int(raw.get("systolic_bp"), 60, 250),
        "diastolic_bp": safe_int(raw.get("diastolic_bp"), 30, 150),
        "blood_sugar": safe_float(raw.get("blood_sugar"), 2.0, 30.0),
        "cholesterol": safe_float(raw.get("cholesterol"), 1.0, 15.0),
        "triglycerides": safe_float(raw.get("triglycerides"), 0.2, 10.0),
        "height_cm": safe_float(raw.get("height_cm"), 100.0, 230.0),
        "weight_kg": safe_float(raw.get("weight_kg"), 30.0, 300.0),
    }


def _extract_health_values_regex(text: str) -> dict:
    result = {
        "systolic_bp": None,
        "diastolic_bp": None,
        "blood_sugar": None,
        "cholesterol": None,
        "triglycerides": None,
        "height_cm": None,
        "weight_kg": None,
    }
    bp = re.search(r"(?:BP|blood\s*pressure|收缩压|血压)?[:\s]*(\d{2,3})\s*/\s*(\d{2,3})", text, re.IGNORECASE)
    if not bp:
        bp = re.search(
            r"(?:SBP|systolic)[:\s]*(\d{2,3}).*?(?:DBP|diastolic)[:\s]*(\d{2,3})",
            text,
            re.IGNORECASE | re.DOTALL,
        )
    if bp:
        s, d = int(bp.group(1)), int(bp.group(2))
        if 60 <= s <= 250 and 30 <= d <= 150:
            result["systolic_bp"] = s
            result["diastolic_bp"] = d
    glucose = re.search(r"(?:glucose|blood\s*sugar|FBG|GLU|空腹血糖|血糖)[^0-9]*(\d+\.?\d*)", text, re.IGNORECASE)
    if glucose:
        v = float(glucose.group(1))
        if v > 30:
            v = round(v / 18.0, 1)
        if 2.0 <= v <= 30.0:
            result["blood_sugar"] = round(v, 1)
    chol = re.search(r"(?:total\s*chol(?:esterol)?|CHOL|TC|总胆固醇)[^0-9]*(\d+\.?\d*)", text, re.IGNORECASE)
    if chol:
        v = float(chol.group(1))
        if v > 20:
            v = round(v / 38.67, 1)
        if 1.0 <= v <= 15.0:
            result["cholesterol"] = round(v, 1)
    trig = re.search(r"(?:triglyceride|TG|TRIG|甘油三酯)[^0-9]*(\d+\.?\d*)", text, re.IGNORECASE)
    if trig:
        v = float(trig.group(1))
        if v > 15:
            v = round(v / 88.57, 1)
        if 0.2 <= v <= 10.0:
            result["triglycerides"] = round(v, 1)
    height = re.search(r"(?:height|Ht|身高)[^0-9]*(\d{3}(?:\.\d)?)\s*(?:cm)?", text, re.IGNORECASE)
    if height:
        v = float(height.group(1))
        if 100 <= v <= 230:
            result["height_cm"] = v
    weight = re.search(r"(?:weight|Wt|体重)[^0-9]*(\d{2,3}\.?\d*)\s*(?:kg)?", text, re.IGNORECASE)
    if weight:
        v = float(weight.group(1))
        if 30 <= v <= 300:
            result["weight_kg"] = round(v, 1)
    return result
