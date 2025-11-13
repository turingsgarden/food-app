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
import time
import requests
import jwt as pyjwt  # 注意避免和 flask-jwt 冲突
from jwt import PyJWKClient
import json
from google.oauth2 import id_token
from google.auth.transport import requests as grequests

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app, supports_credentials=True)
verification_store = {}

APPLE_KEYS = None
APPLE_KEYS_LAST_FETCH = 0

# JWT Configuration
app.config['SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'your-secret-key-change-this')
app.config['JWT_EXPIRATION_HOURS'] = 24 * 7  # 7 days

# Configure MongoDB with error handling and retry logic
def init_mongodb():
    """Initialize MongoDB connection with comprehensive error handling"""
    try:
        mongo_uri = os.getenv("MONGO_URI")
        if not mongo_uri:
            print("❌ MONGO_URI environment variable not set!")
            return None, None, None, None, None
        
        print(f"🔍 Attempting MongoDB connection...")
        print(f"🔍 URI format check: {mongo_uri.startswith('mongodb')}")
        
        client = MongoClient(
            mongo_uri,
            maxPoolSize=10,
            minPoolSize=1,
            maxIdleTimeMS=45000,
            serverSelectionTimeoutMS=15000,  # Increased timeout
            connectTimeoutMS=15000,
            socketTimeoutMS=15000,
            retryWrites=True,
            w='majority'
        )
        
        # Test connection with explicit timeout
        client.admin.command('ping')
        print("✅ MongoDB connected successfully")
        
        db = client[os.getenv("MONGO_DB", "food-app-swift")]
        
        # Initialize collections
        users_collection = db["users"]
        profiles_collection = db["profiles"] 
        meals_collection = db["meals"]
        
        return client, db, users_collection, profiles_collection, meals_collection
        
    except Exception as e:
        print(f"❌ MongoDB connection failed: {str(e)}")
        print(f"❌ Error type: {type(e).__name__}")
        # Return dummy objects to prevent app crash
        return None, None, None, None, None

# Initialize MongoDB
client, db, users_collection, profiles_collection, meals_collection = init_mongodb()

# Only create indexes if connection successful
if client is not None and users_collection is not None:
    try:
        users_collection.create_index("email", unique=True)
        profiles_collection.create_index("user_id")
        meals_collection.create_index([("user_id", 1), ("saved_at", -1)])
        print("✅ Database indexes created successfully")
    except Exception as e:
        print(f"⚠️ Index creation failed (may already exist): {str(e)}")
else:
    print("⚠️ MongoDB not available - app will run but database operations will fail")
    # Create dummy collections to prevent import errors
    users_collection = None
    profiles_collection = None
    meals_collection = None

# Configure Gemini for nutrition recalculation
try:
    gemini_api_key = os.getenv("GEMINI_API_KEY")
    if gemini_api_key:
        genai.configure(api_key=gemini_api_key)
        gemini_model = genai.GenerativeModel('gemini-2.0-flash')
        print("✅ Gemini AI configured successfully")
    else:
        print("⚠️ GEMINI_API_KEY not found - AI features will be disabled")
        gemini_model = None
except Exception as e:
    print(f"❌ Gemini configuration failed: {str(e)}")
    gemini_model = None

# Database connection checker decorator
def db_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if client is None or db is None:  # Changed from 'if not client or not db:'
            return jsonify({'error': 'Database connection not available'}), 503
        return f(*args, **kwargs)
    return decorated

# HTTPS Enforcement Middleware
@app.before_request
def force_https():
    # Skip HTTPS enforcement for local development
    if os.getenv('ENVIRONMENT', 'development') == 'production':
        if not request.is_secure and request.headers.get('X-Forwarded-Proto') != 'https':
            return redirect(request.url.replace('http://', 'https://'))

# JWT Token Required Decorator
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        
        # Get token from header
        if 'Authorization' in request.headers:
            auth_header = request.headers['Authorization']
            try:
                token = auth_header.split(' ')[1]  # Bearer <token>
            except IndexError:
                return jsonify({'error': 'Invalid token format'}), 401
        
        if not token:
            return jsonify({'error': 'Token is missing'}), 401
        
        try:
            # Decode token
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
            current_user_id = data['user_id']
            
            # Add user_id to request context
            request.user_id = current_user_id
            
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token has expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401
        
        return f(*args, **kwargs)
    
    return decorated

# Helper function to generate JWT token
def generate_token(user_id):
    payload = {
        'user_id': str(user_id),
        'exp': datetime.utcnow() + timedelta(hours=app.config['JWT_EXPIRATION_HOURS'])
    }
    token = jwt.encode(payload, app.config['SECRET_KEY'], algorithm='HS256')
    return token

@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "ok", "timestamp": datetime.now().isoformat()}), 200

@app.route("/")
def home():
    return {"message": "Food Analyzer Backend is Running", "version": "3.0", "security": "enhanced"}, 200

@app.route("/health", methods=["GET"])
def health():
    try:
        # Check MongoDB connection
        mongodb_status = "disconnected"
        if client:
            try:
                client.admin.command('ping')
                mongodb_status = "connected"
            except:
                mongodb_status = "connection_failed"
        
        # Check Gemini API key
        gemini_ok = bool(os.getenv("GEMINI_API_KEY"))
        
        return jsonify({
            "status": "healthy" if mongodb_status == "connected" else "degraded",
            "mongodb": mongodb_status,
            "gemini": "configured" if gemini_ok else "missing API key",
            "security": "jwt+bcrypt",
            "https": "enforced" if os.getenv('ENVIRONMENT') == 'production' else "development",
            "timestamp": datetime.now().isoformat()
        }), 200 if mongodb_status == "connected" else 503
        
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }), 503

@app.route("/debug-env", methods=["GET"])
def debug_env():
    """Debug endpoint to check environment variables"""
    return jsonify({
        "has_mongo_uri": bool(os.getenv("MONGO_URI")),
        "mongo_uri_prefix": os.getenv("MONGO_URI", "")[:50] if os.getenv("MONGO_URI") else "None",
        "has_gemini_key": bool(os.getenv("GEMINI_API_KEY")),
        "environment": os.getenv("ENVIRONMENT", "not-set"),
        "mongo_db": os.getenv("MONGO_DB", "not-set"),
        "jwt_secret_set": bool(os.getenv("JWT_SECRET_KEY"))
    }), 200

@app.route("/register", methods=["POST"])
@db_required
def register():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        # Validate required fields
        required_fields = ["name", "email", "password"]
        missing_fields = [field for field in required_fields if field not in data or not data[field]]
        if missing_fields:
            return jsonify({"error": f"Missing fields: {', '.join(missing_fields)}"}), 400
            
        # Check if email already exists
        if users_collection.find_one({"email": data["email"]}):
            return jsonify({"error": "Email already registered"}), 409

        # Hash password with bcrypt
        hashed_pw = bcrypt.hashpw(data["password"].encode('utf-8'), bcrypt.gensalt())
        
        user = {
            "name": data["name"],
            "email": data["email"],
            "password": hashed_pw,  # Store as bytes
            "created_at": datetime.now().isoformat()
        }
        
        result = users_collection.insert_one(user)
        
        # Generate JWT token
        token = generate_token(result.inserted_id)
        
        return jsonify({
            "user_id": str(result.inserted_id), 
            "name": data["name"],
            "token": token
        }), 200
        
    except Exception as e:
        print(f"❌ Register error: {str(e)}")
        return jsonify({"error": "Registration failed"}), 500

@app.route("/login", methods=["POST"])
@db_required
def login():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        # Validate required fields
        if not data.get("email") or not data.get("password"):
            return jsonify({"error": "Email and password required"}), 400
            
        user = users_collection.find_one({"email": data["email"]})
        if not user:
            return jsonify({"error": "Invalid email or password"}), 401

        # Check password with bcrypt
        if not bcrypt.checkpw(data["password"].encode('utf-8'), user["password"]):
            return jsonify({"error": "Invalid email or password"}), 401

        # Generate JWT token
        token = generate_token(user["_id"])

        return jsonify({
            "user_id": str(user["_id"]), 
            "name": user["name"],
            "token": token
        }), 200
        
    except Exception as e:
        print(f"❌ Login error: {str(e)}")
        return jsonify({"error": "Login failed"}), 500

@app.route("/save-profile", methods=["POST"])
@token_required
@db_required
def save_profile():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty or invalid JSON"}), 400

        # Use user_id from JWT token
        user_id = request.user_id
        
        # Remove user_id from data if present
        profile_data = {k: v for k, v in data.items() if k != "user_id"}
        profile_data["updated_at"] = datetime.now().isoformat()
        
        profiles_collection.update_one(
            {"user_id": user_id},
            {"$set": profile_data},
            upsert=True
        )
        
        return jsonify({"message": "Profile saved"}), 200
    except Exception as e:
        print(f"❌ Save profile error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/get-profile", methods=["GET"])
@token_required
@db_required
def get_profile():
    try:
        # Use user_id from JWT token
        user_id = request.user_id

        profile = profiles_collection.find_one({"user_id": user_id})
        if not profile:
            return jsonify({"error": "Profile not found"}), 404

        profile["_id"] = str(profile["_id"])
        return jsonify(profile), 200
    except Exception as e:
        print(f"❌ Get profile error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/analyze", methods=["POST"])
@token_required
def analyze():
    """Image analysis endpoint - enhanced with JWT auth"""
    try:
        if not gemini_model:
            return jsonify({"error": "AI service unavailable"}), 503
            
        if "image" not in request.files:
            return jsonify({"error": "No image part in the request"}), 400

        image_file = request.files["image"]
        user_id = request.user_id  # From JWT token

        # Validate file size (limit to 10MB)
        image_file.seek(0, 2)  # Seek to end
        file_size = image_file.tell()
        image_file.seek(0)  # Reset to beginning
        
        if file_size > 10 * 1024 * 1024:  # 10MB limit
            return jsonify({"error": "Image too large. Please use an image under 10MB"}), 413

        if file_size < 1024:  # Too small
            return jsonify({"error": "Image too small. Please use a clearer image"}), 400

        filename = f"image_{int(time.time())}.png"
        image_path = os.path.join("/tmp", filename)
        image_file.save(image_path)

        print(f"📸 Saved image to: {image_path} (size: {file_size / 1024 / 1024:.2f}MB)")

        # Validate image before analysis
        is_valid, validation_msg = validate_image_for_analysis(image_path)
        if not is_valid:
            try:
                os.remove(image_path)
            except:
                pass
            return jsonify({"error": f"Invalid image: {validation_msg}"}), 400

        # Perform analysis with timeout handling
        from concurrent.futures import ThreadPoolExecutor, TimeoutError
        import concurrent.futures
        
        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(full_image_analysis, image_path, user_id)
            try:
                # Give it 90 seconds to complete
                result = future.result(timeout=90)
                
                # Check if analysis actually succeeded
                if "error" in result:
                    print(f"⚠️ Analysis contained errors: {result.get('error', 'Unknown error')}")
                    # Clean up and return error
                    try:
                        os.remove(image_path)
                    except:
                        pass
                    return jsonify({
                        "error": f"Analysis failed: {result.get('error', 'Unknown error')}",
                        "suggestion": "Please try with a clearer image of food"
                    }), 500
                
                # Validate that we got meaningful results
                if (result.get("dish_prediction", "").lower().startswith("analysis failed") or
                    result.get("dish_prediction", "").lower().startswith("could not identify") or
                    result.get("dish_prediction", "").lower().startswith("unable to analyze")):
                    try:
                        os.remove(image_path)
                    except:
                        pass
                    return jsonify({
                        "error": "Unable to analyze this image",
                        "suggestion": "Please ensure the image clearly shows food items"
                    }), 422
                
            except concurrent.futures.TimeoutError:
                print("⏱️ Analysis timeout")
                try:
                    os.remove(image_path)
                except:
                    pass
                return jsonify({
                    "error": "Analysis timeout",
                    "suggestion": "Please try with a simpler or clearer image"
                }), 408
        
        result["user_id"] = user_id
        print(f"✅ Analysis completed for {filename}")
        print(f"📊 Dish: {result.get('dish_prediction', 'Unknown')}")
        print(f"📊 Hidden ingredients: {result.get('hidden_ingredients', 'None')[:100]}...")
        print(f"⏱️ Analysis time: {result.get('analysis_time', 0):.2f}s")
        
        # Debug: Check if hidden ingredients exist
        if result.get('hidden_ingredients'):
            print(f"🔍 Hidden ingredients length: {len(result['hidden_ingredients'])}")
            print(f"🔍 Hidden ingredients preview: {result['hidden_ingredients'][:200]}...")
        else:
            print("⚠️ No hidden ingredients in result")
        
        # ADD THIS NEW DEBUG SECTION
        print(f"📊 NUTRITION INFO DEBUG:")
        nutrition_info = result.get('nutrition_info', '')
        print(f"📊 Nutrition info exists: {bool(nutrition_info)}")
        print(f"📊 Nutrition info length: {len(nutrition_info)}")
        print(f"📊 Nutrition info content:\n{nutrition_info}")
        
        # Also check if it's properly formatted
        if nutrition_info:
            lines = nutrition_info.split('\n')
            print(f"📊 Nutrition lines count: {len(lines)}")
            for i, line in enumerate(lines[:3]):  # Show first 3 lines
                print(f"📊 Line {i}: '{line}'")
        
        # Clean up
        try:
            os.remove(image_path)
        except:
            pass
            
        return jsonify(result), 200

    except Exception as e:
        print("❌ analyze Exception:", str(e))
        traceback.print_exc()
        # Clean up on error
        try:
            if 'image_path' in locals():
                os.remove(image_path)
        except:
            pass
        return jsonify({
            "error": "Analysis failed",
            "details": str(e)
        }), 500

def compress_base64_image(base64_str, quality=5):
    try:
        image_data = base64.b64decode(base64_str)
        image = Image.open(BytesIO(image_data)).convert("RGB")
        buffer = BytesIO()
        image.save(buffer, format="JPEG", quality=quality)
        compressed_data = buffer.getvalue()
        return base64.b64encode(compressed_data).decode("utf-8")
    except Exception as e:
        print("❌ Compression Error:", str(e))
        return None

@app.route("/save-meal", methods=["POST"])
@token_required
@db_required
def save_meal():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
            
        required = ["dish_prediction", "image_description", "nutrition_info"]
        missing = [k for k in required if k not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400

        # Use user_id from JWT token
        user_id = request.user_id

        # Process images
        image = data.get("image", None)
        image_full = data.get("image_full") or image
        image_thumb = data.get("image_thumb") or (compress_base64_image(image) if image else None)

        # Log the nutrition info being saved
        print(f"📊 Saving meal with nutrition info: {data['nutrition_info'][:200]}...")
        print(f"📊 Nutrition info length: {len(data['nutrition_info'])}")

        # Build meal document
        meal = {
            "user_id": user_id,
            "dish_prediction": data["dish_prediction"],
            "image_description": data["image_description"],
            "nutrition_info": data["nutrition_info"],  # Make sure this has the recalculated values
            "hidden_ingredients": data.get("hidden_ingredients", ""),
            "image_full": image_full,
            "image_thumb": image_thumb,
            "meal_type": data.get("meal_type", "Lunch"),
            "saved_at": data.get("saved_at", datetime.now().isoformat()),
            "analysis_method": "dynamic_ai",
            "contains_hardcoded_values": False
        }

        result = meals_collection.insert_one(meal)
        
        print(f"✅ Meal saved successfully with ID: {result.inserted_id}")
        print(f"📊 Saved nutrition: {meal['nutrition_info'][:100]}...")
        
        return jsonify({
            "message": "Meal saved successfully",
            "meal_id": str(result.inserted_id)
        }), 200
        
    except Exception as e:
        print(f"❌ Error in save_meal: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/user-meals", methods=["GET"])
@token_required
@db_required
def get_user_meals():
    try:
        # Use user_id from JWT token
        user_id = request.user_id
        print(f"📊 Fetching meals for user: {user_id}")

        # Query meals for the user, sorted by date
        meals = list(meals_collection.find(
            {"user_id": user_id}
        ).sort("saved_at", -1))
        
        print(f"📊 Found {len(meals)} meals")
        
        # Process each meal to ensure compatibility
        processed_meals = []
        for meal in meals:
            # Convert ObjectId to string
            meal["_id"] = str(meal["_id"])
            
            # Log nutrition info for debugging
            if "nutrition_info" in meal:
                print(f"📊 Meal {meal['dish_prediction'][:30]} nutrition: {meal['nutrition_info'][:100]}...")
            
            # Handle different image storage formats
            if "image" in meal and isinstance(meal["image"], bytes):
                meal["image_thumb"] = base64.b64encode(meal["image"]).decode('utf-8')
                meal["image_full"] = meal["image_thumb"]
                del meal["image"]
            
            # Ensure all required fields exist
            meal.setdefault("dish_prediction", meal.get("dish", "Unknown Dish"))
            meal.setdefault("image_description", meal.get("visible_ingredients", ""))
            meal.setdefault("hidden_ingredients", "")
            meal.setdefault("nutrition_info", "")
            meal.setdefault("meal_type", "Lunch")
            
            # Handle timestamp/saved_at field
            if "timestamp" in meal:
                if hasattr(meal["timestamp"], 'isoformat'):
                    meal["saved_at"] = meal["timestamp"].isoformat()
                else:
                    meal["saved_at"] = str(meal["timestamp"])
            else:
                meal.setdefault("saved_at", "")
            
            # Remove fields that iOS doesn't expect
            fields_to_remove = ["timestamp", "visible_ingredients", "image_filename", "dish"]
            for field in fields_to_remove:
                meal.pop(field, None)
            
            # Ensure image fields exist
            meal.setdefault("image_full", "")
            meal.setdefault("image_thumb", "")
            
            processed_meals.append(meal)

        print(f"✅ Returning {len(processed_meals)} processed meals")
        
        return jsonify(processed_meals), 200
        
    except Exception as e:
        print(f"❌ Error in get_user_meals: {str(e)}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/update-meal", methods=["PUT"])
@token_required
@db_required
def update_meal():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        meal_id = data.get("meal_id")
        if not meal_id:
            return jsonify({"error": "Missing meal_id"}), 400
        
        print(f"📊 Updating meal {meal_id}")
        print(f"📊 Nutrition info received: {data.get('nutrition_info', '')[:200]}...")
        
        # Verify meal belongs to user
        meal = meals_collection.find_one({"_id": ObjectId(meal_id)})
        if not meal or meal["user_id"] != request.user_id:
            return jsonify({"error": "Meal not found or unauthorized"}), 404
        
        # Prepare update data - include ALL fields that can be updated
        update_data = {}
        if "dish_prediction" in data:
            update_data["dish_prediction"] = data["dish_prediction"]
        if "image_description" in data:
            update_data["image_description"] = data["image_description"]
        if "hidden_ingredients" in data:
            update_data["hidden_ingredients"] = data["hidden_ingredients"]
        if "nutrition_info" in data:
            update_data["nutrition_info"] = data["nutrition_info"]
            print(f"📊 Updating nutrition to: {data['nutrition_info'][:100]}...")
        if "meal_type" in data:
            update_data["meal_type"] = data["meal_type"]
            
        update_data["updated_at"] = datetime.now().isoformat()
        update_data["last_modified_method"] = "user_edit"
        
        # Update meal in database
        result = meals_collection.update_one(
            {"_id": ObjectId(meal_id)},
            {"$set": update_data}
        )
        
        if result.modified_count > 0:
            print(f"✅ Meal {meal_id} updated successfully")
            print(f"📊 Updated fields: {list(update_data.keys())}")
            return jsonify({"message": "Meal updated successfully"}), 200
        else:
            print(f"⚠️ No changes made to meal {meal_id}")
            return jsonify({"error": "Meal not found or no changes made"}), 404
            
    except Exception as e:
        print(f"❌ Error in update_meal: {str(e)}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route("/delete-meal", methods=["DELETE"])
@token_required
@db_required
def delete_meal():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        meal_id = data.get("meal_id")
        if not meal_id:
            return jsonify({"error": "Missing meal_id"}), 400
        
        # Verify meal belongs to user
        meal = meals_collection.find_one({"_id": ObjectId(meal_id)})
        if not meal or meal["user_id"] != request.user_id:
            return jsonify({"error": "Meal not found or unauthorized"}), 404
        
        # Delete meal from database
        result = meals_collection.delete_one({"_id": ObjectId(meal_id)})
        
        if result.deleted_count > 0:
            return jsonify({"message": "Meal deleted successfully"}), 200
        else:
            return jsonify({"error": "Meal not found"}), 404
            
    except Exception as e:
        print(f"❌ Error in delete_meal: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/recalculate-nutrition", methods=["POST"])
@token_required
def recalculate_nutrition():
    """Fully dynamic nutrition recalculation endpoint"""
    try:
        if not gemini_model:
            return jsonify({"error": "AI service unavailable"}), 503
            
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        ingredients = data.get("ingredients", "")
        
        if not ingredients:
            return jsonify({"error": "No ingredients provided"}), 400
        
        print(f"🔄 Recalculating nutrition for user {request.user_id}")
        print(f"📋 Ingredients received:\n{ingredients}")
        
        # Use enhanced recalculation from model_pipeline
        from model_pipeline import recalculate_nutrition_enhanced
        
        try:
            nutrition_info = recalculate_nutrition_enhanced(ingredients)
            
            print(f"✅ Recalculated nutrition: {nutrition_info[:200]}...")
            
            # Check if recalculation failed
            if "Recalculation failed" in nutrition_info:
                return jsonify({
                    "error": "Nutrition recalculation failed",
                    "details": "Unable to calculate nutrition from provided ingredients"
                }), 500
            
            return jsonify({
                "nutrition_info": nutrition_info,
                "calculation_method": "dynamic_ai",
                "contains_hardcoded_values": False
            }), 200
            
        except Exception as e:
            print(f"❌ Recalculation error: {str(e)}")
            return jsonify({
                "error": "Nutrition recalculation failed",
                "details": str(e)
            }), 500
            
    except Exception as e:
        print(f"❌ Error in recalculate_nutrition: {str(e)}")
        return jsonify({"error": str(e)}), 500

# Add these endpoints to your app.py file

@app.route("/add-exercise", methods=["POST"])
@token_required
@db_required
def add_exercise():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        required = ["exercise_type", "duration"]
        missing = [k for k in required if k not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400
        
        exercise = {
            "user_id": request.user_id,
            "exercise_type": data["exercise_type"],
            "duration": data["duration"],
            "intensity": data.get("intensity", "Moderate"),
            "calories_burned": data.get("calories_burned", 0),
            "notes": data.get("notes", ""),
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())
        }
        
        # Create exercise collection if it doesn't exist
        exercises_collection = db["exercise"]
        exercises_collection.create_index([("user_id", 1), ("recorded_at", -1)])
        
        result = exercises_collection.insert_one(exercise)
        return jsonify({
            "message": "Exercise added successfully",
            "exercise_id": str(result.inserted_id)
        }), 200
        
    except Exception as e:
        print(f"❌ Error in add_exercise: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/user-exercise", methods=["GET"])
@token_required
@db_required
def get_user_exercise():
    try:
        exercises_collection = db["exercise"]
        exercises = list(exercises_collection.find(
            {"user_id": request.user_id}
        ).sort("recorded_at", -1))
        
        for exercise in exercises:
            exercise["_id"] = str(exercise["_id"])
        
        return jsonify(exercises), 200
        
    except Exception as e:
        print(f"❌ Error in get_user_exercise: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/add-water", methods=["POST"])
@token_required
@db_required
def add_water():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        required = ["amount"]
        missing = [k for k in required if k not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400
        
        water_entry = {
            "user_id": request.user_id,
            "amount": data["amount"],
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())
        }
        
        # Create water collection if it doesn't exist
        water_collection = db["water"]
        water_collection.create_index([("user_id", 1), ("recorded_at", -1)])
        
        result = water_collection.insert_one(water_entry)
        return jsonify({
            "message": "Water intake added successfully",
            "water_id": str(result.inserted_id)
        }), 200
        
    except Exception as e:
        print(f"❌ Error in add_water: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/user-water", methods=["GET"])
@token_required
@db_required
def get_user_water():
    try:
        water_collection = db["water"]
        water_entries = list(water_collection.find(
            {"user_id": request.user_id}
        ).sort("recorded_at", -1))
        
        for entry in water_entries:
            entry["_id"] = str(entry["_id"])
        
        return jsonify(water_entries), 200
        
    except Exception as e:
        print(f"❌ Error in get_user_water: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/add-weight", methods=["POST"])
@token_required
@db_required
def add_weight():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Empty request"}), 400
        
        required = ["weight"]
        missing = [k for k in required if k not in data]
        if missing:
            return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400
        
        weight_entry = {
            "user_id": request.user_id,
            "weight": data["weight"],
            "recorded_at": data.get("recorded_at", datetime.now().isoformat())
        }
        
        # Create weight collection if it doesn't exist
        weight_collection = db["weight"]
        weight_collection.create_index([("user_id", 1), ("recorded_at", -1)])
        
        result = weight_collection.insert_one(weight_entry)
        return jsonify({
            "message": "Weight entry added successfully",
            "weight_id": str(result.inserted_id)
        }), 200
        
    except Exception as e:
        print(f"❌ Error in add_weight: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/user-weight", methods=["GET"])
@token_required
@db_required
def get_user_weight():
    try:
        weight_collection = db["weight"]
        weight_entries = list(weight_collection.find(
            {"user_id": request.user_id}
        ).sort("recorded_at", -1))
        
        for entry in weight_entries:
            entry["_id"] = str(entry["_id"])
        
        return jsonify(weight_entries), 200
        
    except Exception as e:
        print(f"❌ Error in get_user_weight: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/dashboard-stats", methods=["GET"])
@token_required
@db_required
def get_dashboard_stats():
    """Get comprehensive dashboard statistics"""
    try:
        # Get current date info
        now = datetime.now()
        today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        week_start = today - timedelta(days=today.weekday())
        month_start = today.replace(day=1)
        
        # Initialize collections
        water_collection = db["water"]
        exercise_collection = db["exercise"]
        weight_collection = db["weight"]
        
        # Get meal stats
        meals = list(meals_collection.find({"user_id": request.user_id}))
        today_meals = [m for m in meals if datetime.fromisoformat(m.get("saved_at", "").replace('Z', '+00:00')).date() == today.date()]
        week_meals = [m for m in meals if datetime.fromisoformat(m.get("saved_at", "").replace('Z', '+00:00')) >= week_start]
        month_meals = [m for m in meals if datetime.fromisoformat(m.get("saved_at", "").replace('Z', '+00:00')) >= month_start]
        
        # Get water stats
        water_entries = list(water_collection.find({"user_id": request.user_id}))
        today_water = sum(w["amount"] for w in water_entries if datetime.fromisoformat(w.get("recorded_at", "").replace('Z', '+00:00')).date() == today.date())
        week_water = sum(w["amount"] for w in water_entries if datetime.fromisoformat(w.get("recorded_at", "").replace('Z', '+00:00')) >= week_start)
        
        # Get exercise stats
        exercise_entries = list(exercise_collection.find({"user_id": request.user_id}))
        today_exercise = sum(e["duration"] for e in exercise_entries if datetime.fromisoformat(e.get("recorded_at", "").replace('Z', '+00:00')).date() == today.date())
        week_exercise = sum(e["duration"] for e in exercise_entries if datetime.fromisoformat(e.get("recorded_at", "").replace('Z', '+00:00')) >= week_start)
        
        # Get weight stats
        weight_entries = list(weight_collection.find({"user_id": request.user_id}).sort("recorded_at", -1))
        current_weight = weight_entries[0]["weight"] if weight_entries else 0
        
        # Calculate streak (simplified)
        streak = 0
        check_date = today
        for i in range(30):  # Check last 30 days
            day_meals = [m for m in meals if datetime.fromisoformat(m.get("saved_at", "").replace('Z', '+00:00')).date() == check_date.date()]
            if day_meals:
                streak += 1
                check_date -= timedelta(days=1)
            else:
                break
        
        return jsonify({
            "today": {
                "meals": len(today_meals),
                "water": today_water,
                "exercise": today_exercise
            },
            "week": {
                "meals": len(week_meals),
                "water": week_water,
                "exercise": week_exercise
            },
            "month": {
                "meals": len(month_meals)
            },
            "current_weight": current_weight,
            "streak": streak,
            "timestamp": now.isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error in get_dashboard_stats: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/user-insights", methods=["GET"])
@token_required
@db_required
def get_user_insights():
    """Get personalized health insights"""
    try:
        # Get user profile for goals
        profile = profiles_collection.find_one({"user_id": request.user_id})
        if not profile:
            return jsonify({"error": "Profile not found"}), 404
        
        calorie_target = profile.get("calorie_target", 2000)
        
        # Get today's data
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        
        # Get today's meals
        today_meals = list(meals_collection.find({
            "user_id": request.user_id,
            "saved_at": {"$gte": today.isoformat()}
        }))
        
        # Calculate today's calories
        today_calories = 0
        for meal in today_meals:
            nutrition = meal.get("nutrition_info", "")
            for line in nutrition.split('\n'):
                if 'calories' in line.lower():
                    parts = line.split('|')
                    if len(parts) >= 2:
                        try:
                            today_calories += int(parts[1].strip())
                        except:
                            pass
        
        # Get today's water
        today_water = sum(
            w["amount"] for w in db["water"].find({
                "user_id": request.user_id,
                "recorded_at": {"$gte": today.isoformat()}
            })
        )
        
        # Get today's exercise
        today_exercise = sum(
            e["duration"] for e in db["exercise"].find({
                "user_id": request.user_id,
                "recorded_at": {"$gte": today.isoformat()}
            })
        )
        
        # Generate insights
        insights = []
        
        # Calorie insights
        if today_calories > calorie_target * 1.2:
            insights.append({
                "type": "warning",
                "title": "High Calorie Intake",
                "message": f"You've consumed {today_calories} calories, which is above your {calorie_target} goal.",
                "icon": "exclamationmark.triangle.fill",
                "color": "red"
            })
        elif today_calories < calorie_target * 0.8:
            insights.append({
                "type": "info",
                "title": "Low Calorie Intake",
                "message": f"You've only consumed {today_calories} calories today. Make sure you're eating enough!",
                "icon": "info.circle.fill",
                "color": "blue"
            })
        
        # Water insights
        if today_water < 1000:
            insights.append({
                "type": "reminder",
                "title": "Stay Hydrated",
                "message": f"You've only had {int(today_water)}ml of water today. Try to drink more!",
                "icon": "drop.fill",
                "color": "blue"
            })
        
        # Exercise insights
        if today_exercise == 0:
            insights.append({
                "type": "motivation",
                "title": "Get Moving",
                "message": "You haven't logged any exercise today. Even a short walk counts!",
                "icon": "figure.walk",
                "color": "green"
            })
        
        return jsonify({
            "insights": insights,
            "today_stats": {
                "calories": today_calories,
                "water": today_water,
                "exercise": today_exercise
            },
            "goals": {
                "calories": calorie_target,
                "water": 2000,
                "exercise": 30
            }
        }), 200
        
    except Exception as e:
        print(f"❌ Error in get_user_insights: {str(e)}")
        return jsonify({"error": str(e)}), 500


from gmail_sender import gmail_send_email

@app.route("/reset_password", methods=["POST"])
def reset_password():
    data = request.get_json()

    # ------------------------------
    # Validate request body
    # ------------------------------
    if not data:
        return jsonify({"error": "Empty request"}), 400

    required_fields = ["email", "new_password"]
    missing = [f for f in required_fields if f not in data or not data[f]]

    if missing:
        return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400

    email = data["email"]
    new_password = data["new_password"]

    if len(new_password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    # ------------------------------
    # Check email exists
    # ------------------------------
    user = users_collection.find_one({"email": email})
    if not user:
        return jsonify({"error": "Email not registered"}), 404

    # ------------------------------
    # Create bcrypt hash (same as register)
    # ------------------------------
    hashed_pw = bcrypt.hashpw(new_password.encode("utf-8"), bcrypt.gensalt())

    # ------------------------------
    # Update in MongoDB
    # ------------------------------
    users_collection.update_one(
        {"email": email},
        {"$set": {"password": hashed_pw}}
    )

    return jsonify({"status": "password_reset_success"}), 200

@app.route("/send_verification", methods=["POST"])
def send_verification():
    print("send_verification is called")
    data = request.get_json()
    email = data.get("email")

    if not email:
        return jsonify({"error": "Email is required"}), 400

    user = users_collection.find_one({"email": email})
    if not user:
        return jsonify({"error": "Email not registered"}), 404

    # 生成6位数字验证码
    code = str(random.randint(100000, 999999))
    expires = int(time.time()) + 300  # 5分钟有效

    # 存储验证码
    verification_store[email] = {"code": code, "expires": expires}

    # 发送邮件
    try:
        sender_email = os.getenv("SENDER_EMAIL")   # 在环境变量中配置
        password = os.getenv("EMAIL_PASSWORD")  

        message = MIMEMultipart("alternative")
        message["Subject"] = "Your Verification Code"
        message["From"] = sender_email
        message["To"] = email

        text = f"""\
Welcome to NutriCam - AI Food Tracker! 🎉

Your verification code is: {code}

This code will expire in 5 minutes. Please enter it soon to complete your registration.

We’re excited to have you join NutriCam — helping you track your meals, understand nutrition, 
and enjoy a smarter journey towards healthy eating.

— The NutriCam Team
"""

        html = f"""\
<html>
  <body style="font-family: Arial, sans-serif; background-color: #f9f9f9; padding: 20px;">
    <div style="max-width: 600px; margin: auto; background: #ffffff; padding: 20px; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
      <h2 style="color: #2c7be5; text-align: center;">Welcome to <span style="color:#28a745;">NutriCam</span> 🎉</h2>
      <p style="font-size: 16px; color: #333;">
        Thank you for signing up for <b>NutriCam - AI Food Tracker</b>!  
      </p>
      <p style="font-size: 16px; color: #333;">Your verification code is:</p>
      <div style="text-align: center; margin: 20px 0;">
        <span style="font-size: 28px; font-weight: bold; color: #28a745; letter-spacing: 3px;">{code}</span>
      </div>
      <p style="font-size: 14px; color: #666; text-align: center;">
        (This code will expire in <b>5 minutes</b>.)
      </p>
      <hr style="margin: 30px 0;">
      <p style="font-size: 16px; color: #333;">
        We’re excited to have you join the NutriCam community.  
        Get ready to track your meals, analyze nutrition, and enjoy a smarter journey towards healthy eating.  
      </p>
      <p style="font-size: 16px; color: #333;">
        See you inside the app! 🍎  
        <br><br>
        — The <b>NutriCam Team</b>
      </p>
    </div>
  </body>
</html>
"""

        message.attach(MIMEText(text, "plain"))
        message.attach(MIMEText(html, "html"))

        context = ssl.create_default_context()
        with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=context) as server:
            server.login(sender_email, password)
            server.sendmail(sender_email, email, message.as_string())

        return jsonify({"status": "ok"}), 200
    except Exception as e:
        print("Error sending email:", e)
        return jsonify({"error": "Failed to send email"}), 500


# 验证验证码
@app.route("/verify_code", methods=["POST"])
def verify_code():
    data = request.get_json()
    email = data.get("email")
    code = data.get("code")

    if not email or not code:
        return jsonify({"error": "Email and code are required"}), 400

    record = verification_store.get(email)
    if not record:
        return jsonify({"error": "No code sent"}), 400

    if int(time.time()) > record["expires"]:
        return jsonify({"error": "Code expired"}), 400

    if record["code"] != code:
        return jsonify({"error": "Invalid code"}), 400

    # 验证通过后，可以删除或保留
    del verification_store[email]
    return jsonify({"status": "verified"}), 200

from flask import request, jsonify
from werkzeug.security import generate_password_hash



def get_apple_public_keys():
    """Fetch and cache Apple's public keys"""
    global APPLE_KEYS, APPLE_KEYS_LAST_FETCH
    now = time.time()
    if APPLE_KEYS and now - APPLE_KEYS_LAST_FETCH < 60 * 60:  # 1小时缓存
        print("🔍 Using cached Apple public keys")
        return APPLE_KEYS
    print("🔍 Fetching Apple public keys from Apple...")
    resp = requests.get("https://appleid.apple.com/auth/keys")
    if resp.status_code == 200:
        APPLE_KEYS = resp.json()["keys"]
        APPLE_KEYS_LAST_FETCH = now
        print("✅ Apple public keys fetched successfully")
        return APPLE_KEYS
    print("❌ Failed to fetch Apple public keys:", resp.text)
    raise Exception("Failed to fetch Apple public keys")


def verify_apple_identity_token(identity_token):
    """Verify Apple identity token and return decoded payload"""
    print("🔍 Verifying Apple identity token...")

    # Apple 提供的 JWKS endpoint
    jwks_url = "https://appleid.apple.com/auth/keys"
    jwks_client = PyJWKClient(jwks_url)

    # 获取 token header（debug）
    header = jwt.get_unverified_header(identity_token)
    print("🔍 Token header:", header)

    try:
        # 根据 token 找到对应的公钥
        signing_key = jwks_client.get_signing_key_from_jwt(identity_token)
        print("🔍 Matching Apple key found for kid:", header.get("kid"))

        # 验证并解码 token
        payload = jwt.decode(
            identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=os.getenv("APPLE_CLIENT_ID"),
            issuer="https://appleid.apple.com"
        )
        print("✅ Token verified successfully. Payload:", payload)

    except Exception as e:
        print("❌ Token verification failed:", str(e))
        raise

    return payload


def print_identity_token_payload(identity_token: str):
    """Decode Apple identity token payload without verifying signature"""
    try:
        # 只解码，不验证
        payload = jwt.decode(identity_token, options={"verify_signature": False})
        print("🔍 Decoded Apple identity token payload:")
        print(json.dumps(payload, indent=4))
        return payload
    except Exception as e:
        print("❌ Failed to decode identity token:", str(e))
        return None
    

@app.route("/apple_login", methods=["POST"])
@db_required
def apple_login():
    try:
        data = request.get_json()
        identity_token = data.get("identityToken")
        email = data.get("email")

        print("🔍 Incoming /apple_login request:", data)
        print("🔍 Identity token present?", bool(identity_token))
        print("🔍 Email provided:", email)

        print_identity_token_payload(identity_token)

        if not identity_token:
            return jsonify({"error": "Missing identityToken"}), 400

        # 验证 identityToken
        try:
            payload = verify_apple_identity_token(identity_token)
            apple_sub = payload["sub"]
            print("✅ Apple token verified. sub =", apple_sub)
        except Exception as e:
            print("❌ Apple token verification failed:", str(e))
            return jsonify({"error": "Invalid Apple identityToken"}), 401

        # 如果 email 为空，生成 fallback
        if not email:
            email = f"{apple_sub}@apple.local"
            print("🔍 No email provided, using fallback:", email)

        # 查找或创建用户
        print("🔍 Looking up user by email:", email)
        user = users_collection.find_one({"email": email})

        if not user:
            print("🔍 No user found, creating new account")
            user_doc = {
                "name": data.get("name", "Apple User"),
                "email": email,
                "apple_sub": apple_sub,
                "password": None,
                "created_at": datetime.now().isoformat()
            }
            result = users_collection.insert_one(user_doc)
            user_id = result.inserted_id
            user_name = user_doc["name"]
            print(f"✅ New user created with _id={user_id}, email={email}")
        else:
            user_id = user["_id"]
            user_name = user.get("name", "Apple User")
            print(f"✅ Existing user found _id={user_id}, email={email}")

        # 生成 JWT
        token = generate_token(user_id)
        print("✅ Generated JWT for user:", token[:30], "...")

        return jsonify({
            "user_id": str(user_id),
            "name": user_name,
            "token": token
        }), 200

    except Exception as e:
        print("❌ Apple login error:", str(e))
        return jsonify({"error": "Apple login failed"}), 500

@app.route("/google_login", methods=["POST"])
@db_required
def google_login():
    try:
        data = request.get_json()
        google_token = data.get("idToken")

        print("🔍 Incoming /google_login request:", data)
        print("🔍 Google token present?", bool(google_token))

        if not google_token:
            return jsonify({"error": "Missing idToken"}), 400

        try:
            print("🔍 Verifying Google idToken...")
            idinfo = id_token.verify_oauth2_token(
                google_token,
                grequests.Request(),
                os.getenv("GOOGLE_CLIENT_ID")  # 确保你在 .env 配置了 GOOGLE_CLIENT_ID
            )
            print("✅ Google token verified successfully")
            print("📝 Full payload:", idinfo)

            google_sub = idinfo["sub"]
            email = idinfo.get("email", f"{google_sub}@google.local")
            print("👤 UserID (sub):", google_sub)
            print("📧 Email:", email)

        except Exception as e:
            print("❌ Google token verification failed:", str(e))
            return jsonify({"error": "Invalid Google identityToken"}), 401

        # 查找或创建用户
        print("🔍 Looking up user by email:", email)
        user = users_collection.find_one({"email": email})

        if not user:
            print("🔍 No user found, creating new account")
            user_doc = {
                "name": data.get("name", idinfo.get("name", "Google User")),
                "email": email,
                "google_sub": google_sub,
                "password": None,
                "created_at": datetime.now().isoformat()
            }
            result = users_collection.insert_one(user_doc)
            user_id = result.inserted_id
            user_name = user_doc["name"]
            print(f"✅ New user created with _id={user_id}, email={email}")
        else:
            user_id = user["_id"]
            user_name = user.get("name", "Google User")
            print(f"✅ Existing user found _id={user_id}, email={email}")

        # 生成 JWT
        token = generate_token(user_id)
        print("✅ Generated JWT for user:", token[:30], "...")

        return jsonify({
            "user_id": str(user_id),
            "name": user_name,
            "token": token
        }), 200

    except Exception as e:
        print("❌ Google login error:", str(e))
        return jsonify({"error": "Google login failed"}), 500
    
    
@app.route("/delete_account", methods=["DELETE"])
@token_required
@db_required
def delete_account():
    """
    Permanently delete user account and all associated data.
    This complies with App Store guidelines 5.1.1(v) for account deletion.
    """
    try:
        user_id = request.user_id
        
        print(f"🗑️ Account deletion request for user_id: {user_id}")
        
        # Verify user exists
        user = users_collection.find_one({"_id": ObjectId(user_id)})
        if not user:
            print(f"❌ User not found: {user_id}")
            return jsonify({"error": "User not found"}), 404
        
        print(f"👤 Deleting account for user: {user.get('name', 'Unknown')} ({user.get('email', 'Unknown')})")
        
        # Delete all user data from all collections
        deletion_results = {}
        
        # 1. Delete user profile
        profile_result = profiles_collection.delete_many({"user_id": user_id})
        deletion_results["profiles"] = profile_result.deleted_count
        print(f"✅ Deleted {profile_result.deleted_count} profile(s)")
        
        # 2. Delete all meals
        meals_result = meals_collection.delete_many({"user_id": user_id})
        deletion_results["meals"] = meals_result.deleted_count
        print(f"✅ Deleted {meals_result.deleted_count} meal(s)")
        
        # 3. Delete exercise records
        if "exercise" in db.list_collection_names():
            exercise_result = db["exercise"].delete_many({"user_id": user_id})
            deletion_results["exercise"] = exercise_result.deleted_count
            print(f"✅ Deleted {exercise_result.deleted_count} exercise record(s)")
        
        # 4. Delete water intake records
        if "water" in db.list_collection_names():
            water_result = db["water"].delete_many({"user_id": user_id})
            deletion_results["water"] = water_result.deleted_count
            print(f"✅ Deleted {water_result.deleted_count} water record(s)")
        
        # 5. Delete weight records
        if "weight" in db.list_collection_names():
            weight_result = db["weight"].delete_many({"user_id": user_id})
            deletion_results["weight"] = weight_result.deleted_count
            print(f"✅ Deleted {weight_result.deleted_count} weight record(s)")
        
        # 6. Finally, delete the user account itself
        user_result = users_collection.delete_one({"_id": ObjectId(user_id)})
        deletion_results["user"] = user_result.deleted_count
        print(f"✅ Deleted user account")
        
        if user_result.deleted_count == 0:
            print(f"❌ Failed to delete user account")
            return jsonify({"error": "Failed to delete user account"}), 500
        
        print(f"🎉 Account deletion completed successfully")
        print(f"📊 Deletion summary: {deletion_results}")
        
        return jsonify({
            "message": "Account deleted successfully",
            "deleted_data": deletion_results,
            "timestamp": datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        print(f"❌ Error in delete_account: {str(e)}")
        traceback.print_exc()
        return jsonify({
            "error": "Account deletion failed",
            "details": str(e)
        }), 500



# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

@app.errorhandler(413)
def payload_too_large(error):
    return jsonify({"error": "Request payload too large"}), 413

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    print(f"🚀 Starting Food Analyzer Backend on port {port}")
    print(f"✅ Enhanced with JWT authentication and bcrypt")
    print(f"🔐 Security: JWT tokens + bcrypt passwords")
    print(f"📱 Compatible with Swift frontend")
    print(f"🗄️ MongoDB: {'✅ Connected' if client else '❌ Not connected'}")
    print(f"🤖 Gemini AI: {'✅ Ready' if gemini_model else '❌ Not configured'}")
    app.run(host="0.0.0.0", port=port, threaded=True)
