from flask import Flask, request, jsonify, redirect
from flask_cors import CORS
from dotenv import load_dotenv
import os
from pymongo import MongoClient
from bson import ObjectId
from model_pipeline import full_image_analysis, validate_image_for_analysis
import base64
import traceback
import time
import threading
from io import BytesIO
from PIL import Image
from datetime import datetime, timedelta
import google.generativeai as genai
import bcrypt
import jwt
from functools import wraps
import random
import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import requests
import json
import hashlib
from pathlib import Path

import threading
from jwt import PyJWKClient
from google.oauth2 import id_token
from google.auth.transport import requests as grequests
from daily_tip_pipeline import generate_daily_tip, daily_tip_chat_reply, generate_content_with_fallback
from health_pipeline import (
    generate_nutrition_targets,
    generate_weekly_meal_plan,
    analyze_meal_photo,
    generate_health_report,
)


from ocr_health_pipeline import (
    HealthOcrApiError,
    HealthOcrConfigurationError,
    process_health_report,
)

# load_dotenv()
load_dotenv(
    Path(__file__).resolve().parent / ".env",
    override=True
)

app = Flask(__name__)
CORS(app, supports_credentials=True)
verification_store = {}
meal_plan_jobs = {}

APPLE_KEYS = None
APPLE_KEYS_LAST_FETCH = 0
MAX_OCR_FILE_BYTES = 10 * 1024 * 1024
app.config["MAX_CONTENT_LENGTH"] = 16 * 1024 * 1024

app.config['SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'your-secret-key-change-this')
app.config['JWT_EXPIRATION_HOURS'] = 24 * 7

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

def init_mongodb():
    try:
        mongo_uri = os.getenv("MONGO_URI")
        if not mongo_uri:
            print("❌ MONGO_URI not set!")
            return None, None, None, None, None, None
        client = MongoClient(
            mongo_uri,
            maxPoolSize=10, minPoolSize=1, maxIdleTimeMS=45000,
            serverSelectionTimeoutMS=15000, connectTimeoutMS=15000,
            socketTimeoutMS=15000, retryWrites=True, w='majority'
        )
        client.admin.command('ping')
        print("✅ MongoDB connected")
        db = client[os.getenv("MONGO_DB", "food-app-swift")]
        return client, db, db["users"], db["profiles"], db["meals"], db["analysis_record"]
    except Exception as e:
        print(f"❌ MongoDB failed: {e}")
        return None, None, None, None, None, None

client, db, users_collection, profiles_collection, meals_collection, analysis_collection = init_mongodb()

if client is not None and users_collection is not None:
    try:
        users_collection.create_index("email", unique=True)
        profiles_collection.create_index("user_id")
        meals_collection.create_index([("user_id", 1), ("saved_at", -1)])
        analysis_collection.create_index([("user_id", 1), ("analyzed_at", -1)])
        db["daily_tips"].create_index([("user_id", 1), ("date_key", 1)], unique=True)
        db["daily_chats"].create_index([("user_id", 1), ("date_key", 1)], unique=True)
        print("✅ Indexes created")
    except Exception as e:
        print(f"⚠️ Index creation: {e}")
else:
    print("⚠️ MongoDB not available")
    users_collection = profiles_collection = meals_collection = analysis_collection = None

try:
    gemini_api_key = os.getenv("GEMINI_API_KEY")
    if gemini_api_key:
        genai.configure(api_key=gemini_api_key)
        gemini_model = genai.GenerativeModel('gemini-2.5-flash-lite')
        print("✅ Gemini configured")
    else:
        print("⚠️ GEMINI_API_KEY not found")
        gemini_model = None
except Exception as e:
    print(f"❌ Gemini failed: {e}")
    gemini_model = None

def db_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if client is None or db is None:
            return jsonify({'error': 'Database not available'}), 503
        return f(*args, **kwargs)
    return decorated

@app.before_request
def force_https():
    if os.getenv('ENVIRONMENT', 'development') == 'production':
        if not request.is_secure and request.headers.get('X-Forwarded-Proto') != 'https':
            return redirect(request.url.replace('http://', 'https://'))

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        if 'Authorization' in request.headers:
            try:
                token = request.headers['Authorization'].split(' ')[1]
            except IndexError:
                return jsonify({'error': 'Invalid token format'}), 401
        if not token:
            return jsonify({'error': 'Token is missing'}), 401
        try:
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
            request.user_id = data['user_id']
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token has expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401
        return f(*args, **kwargs)
    return decorated

def generate_token(user_id):
    payload = {
        'user_id': str(user_id),
        'exp': datetime.utcnow() + timedelta(hours=app.config['JWT_EXPIRATION_HOURS'])
    }
    return jwt.encode(payload, app.config['SECRET_KEY'], algorithm='HS256')

# ── Basic Routes ──

@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok", "timestamp": datetime.now().isoformat()}), 200

@app.route("/")
def home():
    return {"message": "Food Analyzer Backend is Running", "version": "3.0"}, 200

@app.route("/health", methods=["GET"])
def health():
    try:
        mongodb_status = "disconnected"
        if client:
            try:
                client.admin.command('ping')
                mongodb_status = "connected"
            except:
                mongodb_status = "connection_failed"
        gemini_ok = bool(os.getenv("GEMINI_API_KEY"))
        return jsonify({
            "status": "healthy" if mongodb_status == "connected" else "degraded",
            "mongodb": mongodb_status,
            "gemini": "configured" if gemini_ok else "missing",
            "timestamp": datetime.now().isoformat()
        }), 200 if mongodb_status == "connected" else 503
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503

@app.route("/debug-env", methods=["GET"])
def debug_env():
    return jsonify({
        "has_mongo_uri": bool(os.getenv("MONGO_URI")),
        "has_gemini_key": bool(os.getenv("GEMINI_API_KEY")),
        "environment": os.getenv("ENVIRONMENT", "not-set"),
        "mongo_db": os.getenv("MONGO_DB", "not-set"),
        "jwt_secret_set": bool(os.getenv("JWT_SECRET_KEY"))
    }), 200

# ── Auth ──

@app.route("/register", methods=["POST"])
@db_required
def register():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        missing = [f for f in ["name", "email", "password"] if not data.get(f)]
        if missing:
            return jsonify({"error": f"Missing: {', '.join(missing)}"}), 400
        if users_collection.find_one({"email": data["email"]}):
            return jsonify({"error": "Email already registered"}), 409
        hashed_pw = bcrypt.hashpw(data["password"].encode('utf-8'), bcrypt.gensalt())
        user = {"name": data["name"], "email": data["email"], "password": hashed_pw,
                "login_methods": ["email"], "created_at": datetime.now().isoformat()}
        result = users_collection.insert_one(user)
        token = generate_token(result.inserted_id)
        return jsonify({"user_id": str(result.inserted_id), "name": data["name"],
                        "email": data["email"], "token": token, "login_methods": ["email"]}), 200
    except Exception as e:
        print(f"❌ Register: {e}")
        return jsonify({"error": "Registration failed"}), 500

@app.route("/login", methods=["POST"])
@db_required
def login():
    try:
        data = request.get_json()
        if not data or not data.get("email") or not data.get("password"):
            return jsonify({"error": "Email and password required"}), 400
        user = users_collection.find_one({"email": data["email"]})
        if not user:
            return jsonify({"error": "Invalid email or password"}), 401
        if "password" not in user or not user["password"]:
            methods = user.get("login_methods", [])
            return jsonify({"error": f"Registered with {', '.join(methods)}"}), 401
        if not bcrypt.checkpw(data["password"].encode('utf-8'), user["password"]):
            return jsonify({"error": "Invalid email or password"}), 401
        login_methods = user.get("login_methods", [])
        if "email" not in login_methods:
            login_methods.append("email")
            users_collection.update_one({"_id": user["_id"]}, {"$set": {"login_methods": login_methods}})
        token = generate_token(user["_id"])
        return jsonify({"user_id": str(user["_id"]), "name": user["name"],
                        "email": user["email"], "token": token, "login_methods": login_methods}), 200
    except Exception as e:
        print(f"❌ Login: {e}")
        return jsonify({"error": "Login failed"}), 500

# ── Profile ──

@app.route("/save-profile", methods=["POST"])
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

@app.route("/get-profile", methods=["GET"])
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

# ── Analyze ──

@app.route("/analyze", methods=["POST"])
@token_required
def analyze():
    try:
        if not os.getenv("GEMINI_API_KEY"):
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
            try: os.remove(image_path)
            except: pass
            return jsonify({"error": f"Invalid image: {msg}"}), 400
        from concurrent.futures import ThreadPoolExecutor
        import concurrent.futures
        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(full_image_analysis, image_path, user_id)
            try:
                result = future.result(timeout=90)
                if "error" in result:
                    try: os.remove(image_path)
                    except: pass
                    return jsonify({"error": f"Analysis failed: {result.get('error')}"}), 500
                if result.get("dish_prediction", "").lower().startswith(("analysis failed", "could not identify", "unable to analyze")):
                    try: os.remove(image_path)
                    except: pass
                    return jsonify({"error": "Unable to analyze image"}), 422
            except concurrent.futures.TimeoutError:
                try: os.remove(image_path)
                except: pass
                return jsonify({"error": "Analysis timeout"}), 408
        result["user_id"] = user_id
        nutrition_info = result.get('nutrition_info', '')
        image_base64 = image_thumb = None
        try:
            image_base64 = image_file_to_base64(image_path)
            image_thumb = compress_base64_image(image_base64)
        except: pass
        try:
            if analysis_collection is not None:
                analysis_collection.insert_one({
                    "user_id": user_id, "dish_prediction": result.get("dish_prediction", ""),
                    "image_description": result.get("image_description", ""),
                    "nutrition_info": nutrition_info, "hidden_ingredients": result.get("hidden_ingredients", ""),
                    "image_full": image_base64, "image_thumb": image_thumb,
                    "meal_type": result.get("meal_type", "Unknown"),
                    "analysis_method": "dynamic_ai", "contains_hardcoded_values": False,
                    "analysis_time": result.get("analysis_time"), "analyzed_at": datetime.now().isoformat()
                })
        except: pass
        try: os.remove(image_path)
        except: pass
        return jsonify(result), 200
    except Exception as e:
        print(f"❌ analyze: {e}")
        traceback.print_exc()
        try:
            if 'image_path' in locals(): os.remove(image_path)
        except: pass
        return jsonify({"error": "Analysis failed", "details": str(e)}), 500

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

# ── Meals ──

@app.route("/save-meal", methods=["POST"])
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
        meal = {"user_id": user_id, "dish_prediction": data["dish_prediction"],
                "image_description": data["image_description"], "nutrition_info": data["nutrition_info"],
                "hidden_ingredients": data.get("hidden_ingredients", ""),
                "image_full": image_full, "image_thumb": image_thumb,
                "meal_type": data.get("meal_type", "Lunch"),
                "saved_at": data.get("saved_at", datetime.now().isoformat()),
                "analysis_method": "dynamic_ai", "contains_hardcoded_values": False}
        result = meals_collection.insert_one(meal)
        return jsonify({"message": "Meal saved", "meal_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/user-meals", methods=["GET"])
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
                meal["image_thumb"] = base64.b64encode(meal["image"]).decode('utf-8')
                meal["image_full"] = meal["image_thumb"]
                del meal["image"]
            meal.setdefault("dish_prediction", meal.get("dish", "Unknown Dish"))
            meal.setdefault("image_description", meal.get("visible_ingredients", ""))
            meal.setdefault("hidden_ingredients", "")
            meal.setdefault("nutrition_info", "")
            meal.setdefault("meal_type", "Lunch")
            if "timestamp" in meal:
                meal["saved_at"] = meal["timestamp"].isoformat() if hasattr(meal["timestamp"], 'isoformat') else str(meal["timestamp"])
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

@app.route("/update-meal", methods=["PUT"])
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

@app.route("/delete-meal", methods=["DELETE"])
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

@app.route("/recalculate-nutrition", methods=["POST"])
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
        return jsonify({"nutrition_info": nutrition_info, "calculation_method": "dynamic_ai",
                        "contains_hardcoded_values": False}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ── Exercise / Water / Weight ──

@app.route("/add-exercise", methods=["POST"])
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
        result = col.insert_one({"user_id": request.user_id, "exercise_type": data["exercise_type"],
            "duration": data["duration"], "intensity": data.get("intensity", "Moderate"),
            "calories_burned": data.get("calories_burned", 0), "notes": data.get("notes", ""),
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())})
        return jsonify({"message": "Exercise added", "exercise_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/user-exercise", methods=["GET"])
@token_required
@db_required
def get_user_exercise():
    try:
        entries = list(db["exercise"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries: e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/add-water", methods=["POST"])
@token_required
@db_required
def add_water():
    try:
        data = request.get_json()
        if not data.get("amount"):
            return jsonify({"error": "Missing amount"}), 400
        col = db["water"]
        col.create_index([("user_id", 1), ("recorded_at", -1)])
        result = col.insert_one({"user_id": request.user_id, "amount": data["amount"],
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())})
        return jsonify({"message": "Water added", "water_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/user-water", methods=["GET"])
@token_required
@db_required
def get_user_water():
    try:
        entries = list(db["water"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries: e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/add-weight", methods=["POST"])
@token_required
@db_required
def add_weight():
    try:
        data = request.get_json()
        if not data.get("weight"):
            return jsonify({"error": "Missing weight"}), 400
        col = db["weight"]
        col.create_index([("user_id", 1), ("recorded_at", -1)])
        result = col.insert_one({"user_id": request.user_id, "weight": data["weight"],
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())})
        return jsonify({"message": "Weight added", "weight_id": str(result.inserted_id)}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/user-weight", methods=["GET"])
@token_required
@db_required
def get_user_weight():
    try:
        entries = list(db["weight"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        for e in entries: e["_id"] = str(e["_id"])
        return jsonify(entries), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ── Dashboard Stats & Insights ──

@app.route("/dashboard-stats", methods=["GET"])
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
            try: return datetime.fromisoformat(s.replace('Z', '+00:00'))
            except: return datetime.min
        today_meals = [m for m in meals if parse_dt(m.get("saved_at","")).date() == today.date()]
        week_meals  = [m for m in meals if parse_dt(m.get("saved_at","")) >= week_start]
        month_meals = [m for m in meals if parse_dt(m.get("saved_at","")) >= month_start]
        water_entries = list(db["water"].find({"user_id": request.user_id}))
        today_water = sum(w["amount"] for w in water_entries if parse_dt(w.get("recorded_at","")).date() == today.date())
        week_water  = sum(w["amount"] for w in water_entries if parse_dt(w.get("recorded_at","")) >= week_start)
        exercise_entries = list(db["exercise"].find({"user_id": request.user_id}))
        today_exercise = sum(e["duration"] for e in exercise_entries if parse_dt(e.get("recorded_at","")).date() == today.date())
        week_exercise  = sum(e["duration"] for e in exercise_entries if parse_dt(e.get("recorded_at","")) >= week_start)
        weight_entries = list(db["weight"].find({"user_id": request.user_id}).sort("recorded_at", -1))
        current_weight = weight_entries[0]["weight"] if weight_entries else 0
        streak = 0
        check_date = today
        for _ in range(30):
            if any(parse_dt(m.get("saved_at","")).date() == check_date.date() for m in meals):
                streak += 1; check_date -= timedelta(days=1)
            else: break
        return jsonify({"today": {"meals": len(today_meals), "water": today_water, "exercise": today_exercise},
                        "week": {"meals": len(week_meals), "water": week_water, "exercise": week_exercise},
                        "month": {"meals": len(month_meals)},
                        "current_weight": current_weight, "streak": streak,
                        "timestamp": now.isoformat()}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/user-insights", methods=["GET"])
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
            for line in meal.get("nutrition_info", "").split('\n'):
                if 'calories' in line.lower():
                    parts = line.split('|')
                    if len(parts) >= 2:
                        try: today_calories += int(parts[1].strip())
                        except: pass
        today_water = sum(w["amount"] for w in db["water"].find({"user_id": request.user_id, "recorded_at": {"$gte": today.isoformat()}}))
        today_exercise = sum(e["duration"] for e in db["exercise"].find({"user_id": request.user_id, "recorded_at": {"$gte": today.isoformat()}}))
        insights = []
        if today_calories > calorie_target * 1.2:
            insights.append({"type": "warning", "title": "High Calorie Intake",
                "message": f"You've consumed {today_calories} kcal, above your {calorie_target} goal.",
                "icon": "exclamationmark.triangle.fill", "color": "red"})
        elif today_calories < calorie_target * 0.8:
            insights.append({"type": "info", "title": "Low Calorie Intake",
                "message": f"Only {today_calories} kcal today. Make sure you're eating enough!",
                "icon": "info.circle.fill", "color": "blue"})
        if today_water < 1000:
            insights.append({"type": "reminder", "title": "Stay Hydrated",
                "message": f"Only {int(today_water)}ml today. Try to drink more!",
                "icon": "drop.fill", "color": "blue"})
        if today_exercise == 0:
            insights.append({"type": "motivation", "title": "Get Moving",
                "message": "No exercise logged today. Even a short walk counts!",
                "icon": "figure.walk", "color": "green"})
        return jsonify({"insights": insights,
                        "today_stats": {"calories": today_calories, "water": today_water, "exercise": today_exercise},
                        "goals": {"calories": calorie_target, "water": 2000, "exercise": 30}}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ── Email / Verification ──

from gmail_sender import gmail_send_email

@app.route("/reset_password", methods=["POST"])
def reset_password():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Empty request"}), 400
    email = data.get("email"); new_password = data.get("new_password")
    if not email or not new_password:
        return jsonify({"error": "Missing fields"}), 400
    if len(new_password) < 6:
        return jsonify({"error": "Password min 6 chars"}), 400
    user = users_collection.find_one({"email": email})
    if not user:
        return jsonify({"error": "Email not registered"}), 404
    hashed_pw = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt())
    users_collection.update_one({"email": email}, {"$set": {"password": hashed_pw}})
    return jsonify({"status": "password_reset_success"}), 200

@app.route("/send_password_reset_code", methods=["POST"])
def send_password_reset_code():
    data = request.get_json()
    email = data.get("email")
    if not email:
        return jsonify({"error": "Email required"}), 400
    user = users_collection.find_one({"email": email})
    if not user:
        return jsonify({"error": "Email not registered"}), 404
    code = str(random.randint(100000, 999999))
    verification_store[email] = {"code": code, "expires": int(time.time()) + 300}
    success = gmail_send_email(
        to_email=email, subject="NutriCam Password Reset Code",
        html_body=f"<p>Your reset code:</p><h2 style='color:#28a745;'>{code}</h2><p>Expires in 5 min.</p>",
        text_body=f"Your NutriCam reset code: {code}. Valid 5 minutes.")
    return jsonify({"status": "ok"} if success else {"error": "Failed to send email"}), 200 if success else 500

@app.route("/send_verification", methods=["POST"])
def send_verification():
    data = request.get_json()
    email = data.get("email")
    if not email:
        return jsonify({"error": "Email required"}), 400
    user = users_collection.find_one({"email": email})
    if not user:
        return jsonify({"error": "Email not registered"}), 404
    code = str(random.randint(100000, 999999))
    verification_store[email] = {"code": code, "expires": int(time.time()) + 300}
    try:
        sender_email = os.getenv("SENDER_EMAIL")
        password = os.getenv("EMAIL_PASSWORD")
        message = MIMEMultipart("alternative")
        message["Subject"] = "Your Verification Code"
        message["From"] = sender_email
        message["To"] = email
        message.attach(MIMEText(f"Your NutriCam code: {code}. Expires in 5 minutes.", "plain"))
        message.attach(MIMEText(f"<h2 style='color:#28a745;'>{code}</h2><p>Expires in 5 min.</p>", "html"))
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=context) as server:
            server.login(sender_email, password)
            server.sendmail(sender_email, email, message.as_string())
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        print(f"❌ send_verification: {e}")
        return jsonify({"error": "Failed to send email"}), 500

@app.route("/verify_code", methods=["POST"])
def verify_code():
    data = request.get_json()
    email = data.get("email"); code = data.get("code")
    if not email or not code:
        return jsonify({"error": "Email and code required"}), 400
    record = verification_store.get(email)
    if not record:
        return jsonify({"error": "No code sent"}), 400
    if int(time.time()) > record["expires"]:
        return jsonify({"error": "Code expired"}), 400
    if record["code"] != code:
        return jsonify({"error": "Invalid code"}), 400
    del verification_store[email]
    return jsonify({"status": "verified"}), 200

# ── Apple / Google Login ──

APPLE_KEYS = None
APPLE_KEYS_LAST_FETCH = 0

def verify_apple_identity_token(identity_token):
    jwks_client = PyJWKClient("https://appleid.apple.com/auth/keys")
    header = jwt.get_unverified_header(identity_token)
    signing_key = jwks_client.get_signing_key_from_jwt(identity_token)
    return jwt.decode(identity_token, signing_key.key, algorithms=["RS256"],
                      audience=os.getenv("APPLE_CLIENT_ID"), issuer="https://appleid.apple.com")

def print_identity_token_payload(identity_token):
    try:
        payload = jwt.decode(identity_token, options={"verify_signature": False})
        print("🔍 Apple token payload:", json.dumps(payload, indent=2))
        return payload
    except Exception as e:
        print(f"❌ Decode token: {e}")
        return None

@app.route("/apple_login", methods=["POST"])
@db_required
def apple_login():
    try:
        data = request.get_json()
        identity_token = data.get("identityToken")
        email = data.get("email")
        print_identity_token_payload(identity_token)
        if not identity_token:
            return jsonify({"error": "Missing identityToken"}), 400
        try:
            payload = verify_apple_identity_token(identity_token)
            apple_sub = payload["sub"]
        except Exception as e:
            return jsonify({"error": "Invalid Apple identityToken"}), 401
        if not email:
            email = f"{apple_sub}@apple.local"
        user = users_collection.find_one({"email": email})
        if user:
            methods = user.get("login_methods", [])
            if "apple" not in methods:
                methods.append("apple")
                users_collection.update_one({"_id": user["_id"]}, {"$set": {"login_methods": methods, "apple_sub": apple_sub}})
            user_id = user["_id"]; user_name = user.get("name", "Apple User")
            login_methods = user.get("login_methods", ["apple"])
        else:
            doc = {"name": data.get("name", "Apple User"), "email": email, "apple_sub": apple_sub,
                   "login_methods": ["apple"], "created_at": datetime.now().isoformat()}
            result = users_collection.insert_one(doc)
            user_id = result.inserted_id; user_name = doc["name"]; login_methods = ["apple"]
        token = generate_token(user_id)
        return jsonify({"user_id": str(user_id), "name": user_name, "email": email,
                        "token": token, "login_methods": login_methods}), 200
    except Exception as e:
        print(f"❌ Apple login: {e}")
        return jsonify({"error": "Apple login failed"}), 500

@app.route("/google_login", methods=["POST"])
@db_required
def google_login():
    try:
        data = request.get_json()
        google_token = data.get("idToken")
        if not google_token:
            return jsonify({"error": "Missing idToken"}), 400
        try:
            idinfo = id_token.verify_oauth2_token(google_token, grequests.Request(), os.getenv("GOOGLE_CLIENT_ID"))
            google_sub = idinfo["sub"]
            email = idinfo.get("email", f"{google_sub}@google.local")
            name = data.get("name", idinfo.get("name", "Google User"))
        except Exception as e:
            return jsonify({"error": "Invalid Google identityToken"}), 401
        user = users_collection.find_one({"email": email})
        if user:
            methods = user.get("login_methods", [])
            if "google" not in methods:
                methods.append("google")
                users_collection.update_one({"_id": user["_id"]}, {"$set": {"login_methods": methods, "google_sub": google_sub}})
            user_id = user["_id"]; user_name = user.get("name", name); login_methods = user.get("login_methods", ["google"])
        else:
            doc = {"name": name, "email": email, "google_sub": google_sub,
                   "login_methods": ["google"], "created_at": datetime.now().isoformat()}
            result = users_collection.insert_one(doc)
            user_id = result.inserted_id; user_name = name; login_methods = ["google"]
        token = generate_token(user_id)
        return jsonify({"user_id": str(user_id), "name": user_name, "email": email,
                        "token": token, "login_methods": login_methods}), 200
    except Exception as e:
        print(f"❌ Google login: {e}")
        return jsonify({"error": "Google login failed"}), 500

# ── Account Management ──

@app.route("/delete_account", methods=["DELETE"])
@token_required
@db_required
def delete_account():
    try:
        user_id = request.user_id
        user = users_collection.find_one({"_id": ObjectId(user_id)})
        if not user:
            return jsonify({"error": "User not found"}), 404
        results = {}
        results["profiles"] = profiles_collection.delete_many({"user_id": user_id}).deleted_count
        results["meals"] = meals_collection.delete_many({"user_id": user_id}).deleted_count
        for col_name in ["exercise", "water", "weight"]:
            if col_name in db.list_collection_names():
                results[col_name] = db[col_name].delete_many({"user_id": user_id}).deleted_count
        result = users_collection.delete_one({"_id": ObjectId(user_id)})
        if result.deleted_count == 0:
            return jsonify({"error": "Failed to delete account"}), 500
        return jsonify({"message": "Account deleted", "deleted_data": results, "timestamp": datetime.now().isoformat()}), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": "Deletion failed", "details": str(e)}), 500

@app.route("/update_name", methods=["POST"])
@token_required
def update_name():
    try:
        data = request.get_json()
        new_name = (data.get("name") or "").strip()
        if len(new_name) < 2:
            return jsonify({"error": "Name min 2 chars"}), 400
        result = users_collection.update_one({"_id": ObjectId(request.user_id)}, {"$set": {"name": new_name}})
        if result.matched_count == 0:
            return jsonify({"error": "User not found"}), 404
        return jsonify({"message": "Name updated", "name": new_name}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/get-login-methods", methods=["GET"])
@token_required
@db_required
def get_login_methods():
    try:
        user = users_collection.find_one({"_id": ObjectId(request.user_id)})
        if not user:
            return jsonify({"error": "User not found"}), 404
        return jsonify({"email": user.get("email", ""), "login_methods": user.get("login_methods", []),
                        "has_password": "password" in user and user["password"] is not None}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/link-email-password", methods=["POST"])
@token_required
@db_required
def link_email_password():
    try:
        data = request.get_json()
        password = data.get("password")
        if not password or len(password) < 6:
            return jsonify({"error": "Password min 6 chars"}), 400
        user = users_collection.find_one({"_id": ObjectId(request.user_id)})
        if not user:
            return jsonify({"error": "User not found"}), 404
        if user.get("password"):
            return jsonify({"error": "Email/password already linked"}), 400
        hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
        methods = user.get("login_methods", [])
        if "email" not in methods: methods.append("email")
        users_collection.update_one({"_id": ObjectId(request.user_id)},
                                     {"$set": {"password": hashed, "login_methods": methods}})
        return jsonify({"success": True, "login_methods": methods}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ── Health Agent Endpoints ──

@app.route("/save-health-profile", methods=["POST"])
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

@app.route("/get-health-profile", methods=["GET"])
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

@app.route("/generate-targets", methods=["POST"])
@token_required
@db_required
def generate_targets():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        result = generate_nutrition_targets(profile=data.get("profile", {}),
                                            goals=data.get("goals", []),
                                            gemini_model=gemini_model)
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

@app.route("/generate-meal-plan", methods=["POST"])
@token_required
@db_required
def generate_meal_plan_route():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        result = generate_weekly_meal_plan(nutrition_plan=data.get("nutrition_plan", {}),
                                           health_profile=data.get("health_profile", {}),
                                           gemini_model=gemini_model)
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

@app.route("/generate-meal-plan-async", methods=["POST"])
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
                result = generate_weekly_meal_plan(
                    nutrition_plan=data.get("nutrition_plan", {}),
                    health_profile=data.get("health_profile", {}),
                    days=data.get("days", 7),
                    meals_per_day=data.get("meals_per_day", 3),
                    gemini_model=gemini_model)
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

@app.route("/meal-plan-status/<job_id>", methods=["GET"])
@token_required
def meal_plan_status(job_id):
    job = meal_plan_jobs.get(job_id)
    if not job:
        return jsonify({"status": "error", "error": "Job not found, please generate again"}), 404
    return jsonify(job), 200

@app.route("/get-meal-plan", methods=["GET"])
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

@app.route("/analyze-meal-photo", methods=["POST"])
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

        user_id   = request.user_id
        meal_type = data.get("meal_type", "lunch")
        date_str  = data.get("date", datetime.now().strftime("%Y-%m-%d"))

        result = analyze_meal_photo(
            image_b64=image_b64,
            meal_type=meal_type,
            planned_meal=data.get("planned_meal", {}),
            remaining_plan=data.get("remaining_plan", []),
            gemini_model=gemini_model,
            user_id=user_id
        )

        log_doc = {
            "user_id": user_id, "date": date_str, "meal_type": meal_type,
            "planned_meal": data.get("planned_meal", {}),
            "detected_foods": result.get("detected_foods", []),
            "estimated_calories": result.get("estimated_calories", 0),
            "estimated_protein": result.get("estimated_protein", 0),
            "estimated_carbs": result.get("estimated_carbs", 0),
            "estimated_fat": result.get("estimated_fat", 0),
            "compliance_score": result.get("compliance_score", 0),
            "compliance_feedback": result.get("compliance_feedback", ""),
            "plan_adjustment_note": result.get("plan_adjustment_note"),
            "saved_at": datetime.now().isoformat()
        }
        db["meal_logs"].insert_one(log_doc)

        estimated_cal = result.get("estimated_calories", 0)
        nutrition_info = result.get("nutrition_info", "")
        if not nutrition_info:
            ep = result.get("estimated_protein", 0)
            ec = result.get("estimated_carbs", 0)
            ef = result.get("estimated_fat", 0)
            nutrition_info = (f"Calories|{estimated_cal}|kcal\nProtein|{ep}|g\n"
                              f"Fat|{ef}|g\nCarbohydrates|{ec}|g\n"
                              f"Fiber|0|g\nSugar|0|g\nSodium|0|mg")

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
            "user_id": user_id, "dish_prediction": dish,
            "image_description": img_desc, "nutrition_info": nutrition_info,
            "hidden_ingredients": result.get("hidden_ingredients", ""),
            "image_full": None, "image_thumb": thumb_b64,
            "meal_type": meal_type.capitalize(),
            "saved_at": datetime.now().isoformat(),
            "analysis_method": "health_agent",
            "from_diet_plan": True,
            "compliance_score": result.get("compliance_score", 0)
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


# ── Health Report Endpoints ──────────────────────────────────────────────────

# ── 修改2 + 修改3：补全 meal_history 查询 + 7天缓存有效期 ──────────────────
@app.route("/generate-health-report", methods=["POST"])
@token_required
@db_required
def generate_health_report_route():
    try:
        data = request.get_json()
        force_regenerate = data.get("force", False) if data else False

        # ── 缓存检查：7天内且非强制 → 直接返回缓存 ──────────────────────────
        if not force_regenerate:
            existing = db["health_reports"].find_one(
                {"user_id": request.user_id},
                sort=[("created_at", -1)]
            )
            if existing:
                cache_valid = False
                try:
                    created_at = datetime.fromisoformat(existing.get("created_at", ""))
                    cache_age_days = (datetime.now() - created_at).days
                    cache_valid = cache_age_days < 7
                except Exception:
                    pass  # 解析失败则视为过期，重新生成

                if cache_valid:
                    existing["_id"] = str(existing["_id"])
                    print(f"📋 Returning cached health report for {request.user_id} "
                          f"(age: {cache_age_days}d)")
                    return jsonify(existing), 200
                else:
                    print(f"♻️ Cache expired ({cache_age_days}d), regenerating report")

        # ── 获取健康档案 ───────────────────────────────────────────────────
        profile = db["health_profiles"].find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Health profile not found"}), 404
        profile.pop("_id", None)

        # ── 获取健康目标 ───────────────────────────────────────────────────
        goals = data.get("goals", []) if data else []
        if not goals:
            plan = db["nutrition_plans"].find_one({"user_id": request.user_id})
            if plan:
                goals = plan.get("goals", [])

        # ── 修改2：补全 meal_history 查询字段 + limit ──────────────────────
        meal_history = list(db["meals"].find(
            {
                "user_id": request.user_id,
                "saved_at": {
                    "$gte": (datetime.now() - timedelta(days=90)).isoformat()
                }
            },
            {
                "dish_prediction":    1,
                "image_description":  1,
                "nutrition_info":     1,
                "hidden_ingredients": 1,  # ← 补上，meal_analyzer 会用到
                "meal_type":          1,
                "saved_at":           1,
                "_id":                0,  # ← 直接在查询里排除，省掉循环 pop
            }
        ).sort("saved_at", -1).limit(200))  # ← 加 limit，防止数据量过大

        print(f"📊 Loaded {len(meal_history)} meals for health report analysis")

        # ── 生成报告 ───────────────────────────────────────────────────────
        result = generate_health_report(
            profile=profile,
            goals=goals,
            gemini_model=gemini_model,
            meal_history=meal_history,
        )

        result["user_id"]   = request.user_id
        result["goals"]     = goals
        result["created_at"] = datetime.now().isoformat()

        # 存储报告（upsert：每个用户只保留最新一份）
        db["health_reports"].update_one(
            {"user_id": request.user_id},
            {"$set": result},
            upsert=True
        )

        # 同步更新 nutrition_plans，让 Dashboard 能读到最新营养目标
        db["nutrition_plans"].update_one(
            {"user_id": request.user_id},
            {"$set": {
                "user_id":       request.user_id,
                "daily_calories": result.get("daily_calories", 2000),
                "protein_g":     result.get("protein_g", 100),
                "carbs_g":       result.get("carbs_g", 250),
                "fat_g":         result.get("fat_g", 65),
                "fiber_g":       result.get("fiber_g", 25),
                "sodium_mg":     result.get("sodium_mg", 2300),
                "goals":         goals,
                "updated_at":    datetime.now().isoformat()
            }},
            upsert=True
        )

        print(f"✅ Health report generated | score={result.get('health_score')} "
              f"| {result.get('daily_calories')} kcal/day "
              f"| foods={len(result.get('recommended_foods', []))}")
        return jsonify(result), 200

    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format, please try again"}), 500
    except Exception as e:
        print(f"❌ generate_health_report_route: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/get-health-report", methods=["GET"])
@token_required
@db_required
def get_health_report():
    try:
        report = db["health_reports"].find_one(
            {"user_id": request.user_id},
            sort=[("created_at", -1)]
        )
        if not report:
            return jsonify({"error": "not found"}), 404
        report["_id"] = str(report["_id"])
        return jsonify(report), 200
    except Exception as e:
        print(f"❌ get_health_report: {e}")
        return jsonify({"error": str(e)}), 500


# ── Daily Health Coach (AI tip + chat) ───────────────────────────────────────

@app.route("/generate-daily-tip", methods=["POST"])
@token_required
@db_required
def generate_daily_tip_route():
    try:
        if not os.getenv("GEMINI_API_KEY"):
            return jsonify({"error": "AI service unavailable"}), 503

        data = request.get_json() or {}
        force = bool(data.get("force", False))
        date_key = data.get("date") or datetime.now().strftime("%Y-%m-%d")

        profile = db["health_profiles"].find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Health profile not found"}), 404
        profile.pop("_id", None)

        # Fingerprint of vitals that influence the tip — if the user edits
        # their profile, the cached tip for today is considered stale.
        fingerprint_fields = {
            k: profile.get(k)
            for k in (
                "age", "sex", "height_cm", "weight_kg",
                "systolic_bp", "diastolic_bp", "fasting_blood_sugar",
                "total_cholesterol", "triglycerides",
                "dietary_preferences", "allergens",
            )
        }
        profile_fingerprint = hashlib.md5(
            json.dumps(fingerprint_fields, sort_keys=True, default=str).encode()
        ).hexdigest()

        if not force:
            cached = db["daily_tips"].find_one(
                {"user_id": request.user_id, "date_key": date_key}
            )
            if cached and cached.get("profile_fingerprint") == profile_fingerprint:
                cached.pop("_id", None)
                print(f"📋 Returning cached daily tip for {request.user_id} @ {date_key}")
                return jsonify(cached.get("tip", cached)), 200
            if cached:
                print(f"♻️ Profile changed — regenerating daily tip for {request.user_id} @ {date_key}")

        health_report = db["health_reports"].find_one(
            {"user_id": request.user_id},
            sort=[("created_at", -1)]
        )
        if health_report:
            health_report.pop("_id", None)

        goals = data.get("goals", [])
        if not goals:
            plan = db["nutrition_plans"].find_one({"user_id": request.user_id})
            if plan:
                goals = plan.get("goals", [])

        meal_history = list(db["meals"].find(
            {
                "user_id": request.user_id,
                "saved_at": {"$gte": (datetime.now() - timedelta(days=30)).isoformat()},
            },
            {
                "dish_prediction": 1,
                "nutrition_info": 1,
                "meal_type": 1,
                "saved_at": 1,
                "_id": 0,
            },
        ).sort("saved_at", -1).limit(100))

        tip = generate_daily_tip(
            profile=profile,
            goals=goals,
            health_report=health_report,
            meal_history=meal_history,
            date_key=date_key,
        )

        record = {
            "user_id": request.user_id,
            "date_key": date_key,
            "tip": tip,
            "profile_fingerprint": profile_fingerprint,
            "created_at": datetime.now().isoformat(),
        }
        db["daily_tips"].update_one(
            {"user_id": request.user_id, "date_key": date_key},
            {"$set": record},
            upsert=True,
        )

        return jsonify(tip), 200
    except json.JSONDecodeError:
        return jsonify({"error": "AI returned invalid format"}), 500
    except Exception as e:
        print(f"❌ generate_daily_tip_route: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/get-daily-tip", methods=["GET"])
@token_required
@db_required
def get_daily_tip_route():
    try:
        date_key = request.args.get("date") or datetime.now().strftime("%Y-%m-%d")
        cached = db["daily_tips"].find_one(
            {"user_id": request.user_id, "date_key": date_key}
        )
        if not cached:
            return jsonify({"error": "not found"}), 404
        return jsonify(cached.get("tip", cached)), 200
    except Exception as e:
        print(f"❌ get_daily_tip_route: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/daily-tip-chat", methods=["POST"])
@token_required
@db_required
def daily_tip_chat_route():
    try:
        if not os.getenv("GEMINI_API_KEY"):
            return jsonify({"error": "AI service unavailable"}), 503

        data = request.get_json() or {}
        messages = data.get("messages", [])
        date_key = data.get("date_key") or datetime.now().strftime("%Y-%m-%d")
        tip_snapshot = data.get("tip_snapshot")

        if not messages:
            return jsonify({"error": "messages required"}), 400

        if not tip_snapshot:
            cached = db["daily_tips"].find_one(
                {"user_id": request.user_id, "date_key": date_key}
            )
            tip_snapshot = (cached or {}).get("tip")

        if not tip_snapshot:
            return jsonify({"error": "Daily tip not found for this date"}), 404

        profile = db["health_profiles"].find_one({"user_id": request.user_id}) or {}
        profile.pop("_id", None)
        health_report = db["health_reports"].find_one(
            {"user_id": request.user_id},
            sort=[("created_at", -1)],
        ) or {}
        health_report.pop("_id", None)

        reply = daily_tip_chat_reply(
            messages=messages,
            tip_snapshot=tip_snapshot,
            profile=profile,
            health_report=health_report,
        )

        now_iso = datetime.now().isoformat()
        stored_messages = []
        for msg in messages:
            stored_messages.append({
                "role": msg.get("role", "user"),
                "text": msg.get("text", ""),
                "ts": msg.get("ts") or now_iso,
            })
        stored_messages.append({
            "role": "coach",
            "text": reply,
            "ts": now_iso,
        })

        db["daily_chats"].update_one(
            {"user_id": request.user_id, "date_key": date_key},
            {
                "$set": {
                    "user_id": request.user_id,
                    "date_key": date_key,
                    "messages": stored_messages,
                    "updated_at": now_iso,
                }
            },
            upsert=True,
        )

        return jsonify({"reply": reply}), 200
    except Exception as e:
        print(f"❌ daily_tip_chat_route: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/get-daily-tip-chat", methods=["GET"])
@token_required
@db_required
def get_daily_tip_chat_route():
    try:
        date_key = request.args.get("date") or datetime.now().strftime("%Y-%m-%d")
        doc = db["daily_chats"].find_one(
            {"user_id": request.user_id, "date_key": date_key}
        )
        if not doc:
            return jsonify({"messages": []}), 200
        return jsonify({"messages": doc.get("messages", [])}), 200
    except Exception as e:
        print(f"❌ get_daily_tip_chat_route: {e}")
        return jsonify({"error": str(e)}), 500


# ── Error Handlers ──

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

@app.errorhandler(413)
def payload_too_large(error):
    return jsonify({"error": "Request payload too large"}), 413





@app.route("/ocr-health-report", methods=["POST"])
@token_required
def ocr_health_report():
    try:
        data = request.get_json(silent=True) or {}

        # Keep compatibility with the existing image_base64 request.
        encoded_file = (
            data.get("image_base64")
            or data.get("file_base64")
        )

        if not encoded_file:
            return jsonify({
                "error": "No image or document was provided."
            }), 400

        if not isinstance(encoded_file, str):
            return jsonify({
                "error": "The uploaded file must be base64 encoded."
            }), 400

        # Support strings such as:
        # data:image/jpeg;base64,/9j/4AAQ...
        if encoded_file.startswith("data:"):
            try:
                encoded_file = encoded_file.split(",", 1)[1]
            except IndexError:
                return jsonify({
                    "error": "Invalid base64 data URL."
                }), 400

        # Remove accidental spaces or line breaks.
        encoded_file = "".join(encoded_file.split())

        try:
            file_bytes = base64.b64decode(
                encoded_file,
                validate=True,
            )
        except Exception:
            return jsonify({
                "error": "The uploaded file contains invalid base64 data."
            }), 400

        if not file_bytes:
            return jsonify({
                "error": "The uploaded file is empty."
            }), 400

        # Base64 is larger than the original file, so check decoded bytes.
        max_file_size = 10 * 1024 * 1024

        if len(file_bytes) > max_file_size:
            return jsonify({
                "error": "File too large. Maximum size is 10 MB."
            }), 413

        filename = data.get("filename") or "upload.jpg"
        mime_type = data.get("mime_type") or "image/jpeg"

        result = process_health_report(
            file_bytes,
            filename=filename,
            mime_type=mime_type,
            include_raw_text=False,
            max_retries=3,
        )

        print(
    "✅ Health OCR completed: "
    f"status={result.get('status')}, "
    f"additional_fields="
    f"{len(result.get('additional_fields', []))}"
)

        return jsonify(result), 200

    except HealthOcrConfigurationError as error:
        print(f"❌ OCR configuration error: {error}")

        return jsonify({
            "error": "OCR service is not configured on the server."
        }), 503

    except HealthOcrApiError as error:
        print(f"❌ Gemini OCR API error: {error}")

        return jsonify({
            "error": "The OCR service could not process the report."
        }), 502

    except ValueError as error:
        # Covers unsupported file types and invalid PDF files.
        return jsonify({
            "error": str(error)
        }), 400

    except Exception as error:
        print(f"❌ Unexpected OCR error: {error}")
        traceback.print_exc()

        return jsonify({
            "error": "Unexpected OCR processing error."
        }), 500

@app.route("/ocr-document", methods=["POST"])
@token_required
def ocr_document():
    """
    PDF/DOCX compatibility endpoint.

    Both file types are processed by the new
    ocr_health_pipeline.process_health_report pipeline.
    """
    try:
        data = request.get_json(silent=True) or {}

        encoded_file = data.get("file_base64")

        if not encoded_file:
            return jsonify({
                "error": "No document was provided."
            }), 400

        if not isinstance(encoded_file, str):
            return jsonify({
                "error": "The document must be base64 encoded."
            }), 400

        if encoded_file.startswith("data:"):
            try:
                encoded_file = encoded_file.split(",", 1)[1]
            except IndexError:
                return jsonify({
                    "error": "Invalid base64 data URL."
                }), 400

        encoded_file = "".join(encoded_file.split())

        try:
            file_bytes = base64.b64decode(
                encoded_file,
                validate=True,
            )
        except Exception:
            return jsonify({
                "error": "The document contains invalid base64 data."
            }), 400

        if not file_bytes:
            return jsonify({
                "error": "The uploaded document is empty."
            }), 400

        max_file_size = 10 * 1024 * 1024

        if len(file_bytes) > max_file_size:
            return jsonify({
                "error": "File too large. Maximum size is 10 MB."
            }), 413

        file_type = str(
            data.get("file_type") or ""
        ).strip().lower()

        file_config = {
            "pdf": (
                "health-report.pdf",
                "application/pdf",
            ),
            "docx": (
                "health-report.docx",
                "application/vnd.openxmlformats-officedocument."
                "wordprocessingml.document",
            ),
        }

        if file_type not in file_config:
            return jsonify({
                "error": "Unsupported file type. Use PDF or DOCX."
            }), 400

        filename, mime_type = file_config[file_type]

        result = process_health_report(
            file_bytes,
            filename=filename,
            mime_type=mime_type,
            include_raw_text=False,
            max_retries=3,
        )

        print(
            "✅ Document OCR completed: "
            f"type={file_type}, "
            f"status={result.get('status')}, "
            f"additional_fields="
            f"{len(result.get('additional_fields', []))}"
        )

        return jsonify(result), 200

    except HealthOcrConfigurationError as error:
        print(f"❌ OCR configuration error: {error}")

        return jsonify({
            "error": "OCR service is not configured."
        }), 503

    except HealthOcrApiError as error:
        print(f"❌ OCR API error: {error}")

        return jsonify({
            "error": "The OCR service could not process the document."
        }), 502

    except ValueError as error:
        return jsonify({
            "error": str(error)
        }), 400

    except Exception as error:
        print(f"❌ Document OCR error: {error}")
        traceback.print_exc()

        return jsonify({
            "error": "Unexpected document OCR error."
        }), 500


@app.route("/meal-insight", methods=["POST"])
@token_required
@db_required
def meal_insight():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        meal_id        = data.get("meal_id", "")
        nutrition_info = data.get("nutrition_info", "")
        dish_name      = data.get("dish_name", "this meal")
        ingredients    = data.get("ingredients", "")
        if not nutrition_info:
            return jsonify({"error": "nutrition_info required"}), 400
        health_profile = db["health_profiles"].find_one({"user_id": request.user_id}) or {}
        health_report  = db["health_reports"].find_one(
            {"user_id": request.user_id}, sort=[("created_at", -1)]) or {}
        if not gemini_model:
            return jsonify({"error": "AI service unavailable"}), 503
        insight = _generate_meal_insight(
            dish_name=dish_name, nutrition_info=nutrition_info, ingredients=ingredients,
            health_profile=health_profile, health_report=health_report, gemini_model=gemini_model)
        insight["meal_id"]      = meal_id
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


def _generate_meal_insight(dish_name, nutrition_info, ingredients,
                            health_profile, health_report, gemini_model):
    profile_ctx = ""
    if health_profile:
        bmi   = health_profile.get("weight_kg", 0) / ((health_profile.get("height_cm", 170) / 100) ** 2)
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

    goals_ctx = ""; daily_cal = 0; daily_prot = 0; daily_sod = 0
    if health_report:
        goals      = health_report.get("goals", [])
        daily_cal  = health_report.get("daily_calories", 0)
        daily_prot = health_report.get("protein_g", 0)
        daily_sod  = health_report.get("sodium_mg", 0)
        goals_ctx  = (f"Daily targets: {daily_cal} kcal, {daily_prot}g protein, {daily_sod}mg sodium. "
                      f"Health goals: {', '.join(goals) if goals else 'general wellness'}.")

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
    raw  = resp.text.strip().replace("```json", "").replace("```", "").strip()
    start = raw.find("{"); end = raw.rfind("}") + 1
    if start >= 0 and end > start:
        raw = raw[start:end]
    result = json.loads(raw)
    result.setdefault("macro_score", {"rating": "N/A", "color": "gray", "summary": ""})
    result.setdefault("highlights", [])
    result.setdefault("warnings",   [])
    result.setdefault("tip", "")
    default_ni = {"status": "ok", "insight": "", "suggestion": ""}
    ni = result.setdefault("nutrient_insights", {})
    for key in ["calories", "protein", "fat", "carbs", "fiber", "sugar", "sodium"]:
        ni.setdefault(key, default_ni.copy())
    return result


def _bmi_category(bmi):
    if bmi < 18.5: return "Underweight"
    if bmi < 25:   return "Normal"
    if bmi < 30:   return "Overweight"
    return "Obese"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5001))
    print(f"🚀 Starting on port {port}")
    print(f"🗄️ MongoDB: {'✅ Connected' if client else '❌ Not connected'}")
    print(f"🤖 Gemini AI: {'✅ Ready' if gemini_model else '❌ Not configured'}")
    app.run(host="0.0.0.0", port=port, threaded=True)
