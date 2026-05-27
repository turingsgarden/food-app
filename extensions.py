from __future__ import annotations

import os

from dotenv import load_dotenv
from pymongo import MongoClient

import google.generativeai as genai

load_dotenv()

# Shared app state (initialized at import-time to match legacy behavior)
client = None
db = None
users_collection = None
profiles_collection = None
meals_collection = None
analysis_collection = None

gemini_model = None

# These stores are used by multiple route modules
verification_store: dict = {}
meal_plan_jobs: dict = {}


def init_mongodb():
    try:
        mongo_uri = os.getenv("MONGO_URI")
        if not mongo_uri:
            print("❌ MONGO_URI not set!")
            return None, None, None, None, None, None
        _client = MongoClient(
            mongo_uri,
            maxPoolSize=10,
            minPoolSize=1,
            maxIdleTimeMS=45000,
            serverSelectionTimeoutMS=15000,
            connectTimeoutMS=15000,
            socketTimeoutMS=15000,
            retryWrites=True,
            w="majority",
        )
        _client.admin.command("ping")
        print("✅ MongoDB connected")
        _db = _client[os.getenv("MONGO_DB", "food-app-swift")]
        return _client, _db, _db["users"], _db["profiles"], _db["meals"], _db["analysis_record"]
    except Exception as e:
        print(f"❌ MongoDB failed: {e}")
        return None, None, None, None, None, None


def init_gemini():
    try:
        gemini_api_key = os.getenv("GEMINI_API_KEY")
        if gemini_api_key:
            genai.configure(api_key=gemini_api_key)
            model = genai.GenerativeModel("gemini-2.5-pro")
            print("✅ Gemini configured")
            return model
        print("⚠️ GEMINI_API_KEY not found")
        return None
    except Exception as e:
        print(f"❌ Gemini failed: {e}")
        return None


def _create_indexes():
    global users_collection, profiles_collection, meals_collection, analysis_collection
    if client is None or users_collection is None:
        print("⚠️ MongoDB not available")
        users_collection = profiles_collection = meals_collection = analysis_collection = None
        return
    try:
        users_collection.create_index("email", unique=True)
        users_collection.create_index("apple_id", unique=True, sparse=True)
        users_collection.create_index("google_id", unique=True, sparse=True)
        profiles_collection.create_index("user_id")
        meals_collection.create_index([("user_id", 1), ("saved_at", -1)])
        analysis_collection.create_index([("user_id", 1), ("analyzed_at", -1)])
        print("✅ Indexes created")
    except Exception as e:
        print(f"⚠️ Index creation: {e}")


def init_extensions():
    """
    Initialize shared connections at import-time (legacy-compatible).
    Kept as a callable so app.py can ensure imports happen deterministically.
    """
    global client, db, users_collection, profiles_collection, meals_collection, analysis_collection, gemini_model

    if client is None and db is None:
        client, db, users_collection, profiles_collection, meals_collection, analysis_collection = init_mongodb()
        _create_indexes()

    if gemini_model is None:
        gemini_model = init_gemini()

    return {
        "client": client,
        "db": db,
        "users_collection": users_collection,
        "profiles_collection": profiles_collection,
        "meals_collection": meals_collection,
        "analysis_collection": analysis_collection,
        "gemini_model": gemini_model,
        "verification_store": verification_store,
        "meal_plan_jobs": meal_plan_jobs,
    }

