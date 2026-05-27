from __future__ import annotations

import json
import os
import re
import time
from datetime import datetime, timedelta
from functools import wraps

import jwt
from jwt import PyJWKClient

from google.oauth2 import id_token
from google.auth.transport import requests as grequests

from extensions import client, db, users_collection

# Apple JWK cache (legacy-compatible behavior)
APPLE_KEYS = None
APPLE_KEYS_LAST_FETCH = 0


def db_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if client is None or db is None:
            from flask import jsonify

            return jsonify({"error": "Database not available"}), 503
        return f(*args, **kwargs)

    return decorated


def token_required(f):
    """
    Decorator: uses current_app config and sets request.user_id.
    """

    @wraps(f)
    def decorated(*args, **kwargs):
        from flask import current_app, jsonify, request

        token = None
        if "Authorization" in request.headers:
            try:
                token = request.headers["Authorization"].split(" ")[1]
            except IndexError:
                return jsonify({"error": "Invalid token format"}), 401
        if not token:
            return jsonify({"error": "Token is missing"}), 401
        try:
            data = jwt.decode(token, current_app.config["SECRET_KEY"], algorithms=["HS256"])
            request.user_id = data["user_id"]
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token has expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401
        return f(*args, **kwargs)

    return decorated


def generate_token(user_id):
    from flask import current_app

    payload = {
        "user_id": str(user_id),
        "exp": datetime.utcnow() + timedelta(hours=current_app.config["JWT_EXPIRATION_HOURS"]),
    }
    return jwt.encode(payload, current_app.config["SECRET_KEY"], algorithm="HS256")


def _normalize_email(email):
    if not email or not isinstance(email, str):
        return None
    normalized = email.strip().lower()
    return normalized if normalized and "@" in normalized else None


def _new_user_provider_defaults():
    return {
        "apple_id": None,
        "google_id": None,
        "apple_sub": None,
        "google_sub": None,
        "auth_providers": [],
    }


def _sync_auth_providers(user):
    methods = list(user.get("login_methods") or [])
    providers = user.get("auth_providers")
    if not providers:
        providers = list(methods)
    return methods, providers


def _find_user_by_provider_id(provider_id, id_field, legacy_field):
    if not provider_id:
        return None
    return users_collection.find_one({"$or": [{id_field: provider_id}, {legacy_field: provider_id}]})


def _find_user_by_email(email):
    normalized = _normalize_email(email)
    if not normalized:
        return None
    return users_collection.find_one({"email": {"$regex": f"^{re.escape(normalized)}$", "$options": "i"}})


def _merge_apple_user(user, apple_sub):
    methods, providers = _sync_auth_providers(user)
    if "apple" not in methods:
        methods.append("apple")
    if "apple" not in providers:
        providers.append("apple")
    update = {
        "login_methods": methods,
        "auth_providers": providers,
        "apple_id": apple_sub,
        "apple_sub": apple_sub,
    }
    users_collection.update_one({"_id": user["_id"]}, {"$set": update})
    user.update(update)
    return user


def _merge_google_user(user, google_sub):
    methods, providers = _sync_auth_providers(user)
    if "google" not in methods:
        methods.append("google")
    if "google" not in providers:
        providers.append("google")
    update = {
        "login_methods": methods,
        "auth_providers": providers,
        "google_id": google_sub,
        "google_sub": google_sub,
    }
    users_collection.update_one({"_id": user["_id"]}, {"$set": update})
    user.update(update)
    return user


def resolve_apple_login(apple_sub, token_email, known_email, display_name):
    user = _find_user_by_provider_id(apple_sub, "apple_id", "apple_sub")
    if user:
        user = _merge_apple_user(user, apple_sub)
        return user, user["email"], user.get("login_methods", ["apple"])

    for candidate in (token_email, known_email):
        user = _find_user_by_email(candidate)
        if user:
            user = _merge_apple_user(user, apple_sub)
            return user, user["email"], user.get("login_methods", ["apple"])

    email = _normalize_email(token_email) or f"{apple_sub}@apple.local"
    doc = {
        "name": display_name or "Apple User",
        "email": email,
        **_new_user_provider_defaults(),
        "apple_id": apple_sub,
        "apple_sub": apple_sub,
        "login_methods": ["apple"],
        "auth_providers": ["apple"],
        "created_at": datetime.now().isoformat(),
    }
    result = users_collection.insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc, email, ["apple"]


def resolve_google_login(google_sub, token_email, known_email, display_name):
    user = _find_user_by_provider_id(google_sub, "google_id", "google_sub")
    if user:
        user = _merge_google_user(user, google_sub)
        return user, user["email"], user.get("login_methods", ["google"])

    for candidate in (token_email, known_email):
        user = _find_user_by_email(candidate)
        if user:
            user = _merge_google_user(user, google_sub)
            return user, user["email"], user.get("login_methods", ["google"])

    email = _normalize_email(token_email) or f"{google_sub}@google.local"
    doc = {
        "name": display_name or "Google User",
        "email": email,
        **_new_user_provider_defaults(),
        "google_id": google_sub,
        "google_sub": google_sub,
        "login_methods": ["google"],
        "auth_providers": ["google"],
        "created_at": datetime.now().isoformat(),
    }
    result = users_collection.insert_one(doc)
    doc["_id"] = result.inserted_id
    return doc, email, ["google"]


def verify_apple_identity_token(identity_token: str) -> dict:
    global APPLE_KEYS, APPLE_KEYS_LAST_FETCH
    now = time.time()
    if not APPLE_KEYS or now - APPLE_KEYS_LAST_FETCH > 60 * 60:
        APPLE_KEYS = PyJWKClient("https://appleid.apple.com/auth/keys")
        APPLE_KEYS_LAST_FETCH = now
    signing_key = APPLE_KEYS.get_signing_key_from_jwt(identity_token).key
    return jwt.decode(
        identity_token,
        signing_key,
        algorithms=["RS256"],
        audience=os.getenv("APPLE_CLIENT_ID"),
        issuer="https://appleid.apple.com",
    )


def print_identity_token_payload(identity_token):
    try:
        payload = jwt.decode(identity_token, options={"verify_signature": False})
        print("🔍 Apple token payload:", json.dumps(payload, indent=2))
        return payload
    except Exception as e:
        print(f"❌ Decode token: {e}")
        return None


def verify_google_id_token(google_token: str) -> dict:
    return id_token.verify_oauth2_token(google_token, grequests.Request(), os.getenv("GOOGLE_CLIENT_ID"))

