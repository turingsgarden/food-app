from __future__ import annotations

import json
import os
import random
import smtplib
import ssl
import time
import traceback
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import bcrypt
from bson import ObjectId
from flask import Blueprint, jsonify, request

from auth_utils import (
    _new_user_provider_defaults,
    db_required,
    generate_token,
    print_identity_token_payload,
    resolve_apple_login,
    resolve_google_login,
    token_required,
    verify_apple_identity_token,
    verify_google_id_token,
)
from extensions import db, meals_collection, profiles_collection, users_collection, verification_store
from gmail_sender import gmail_send_email

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/register", methods=["POST"])
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
        hashed_pw = bcrypt.hashpw(data["password"].encode("utf-8"), bcrypt.gensalt())
        user = {
            "name": data["name"],
            "email": data["email"],
            "password": hashed_pw,
            "login_methods": ["email"],
            "auth_providers": ["email"],
            **_new_user_provider_defaults(),
            "created_at": datetime.now().isoformat(),
        }
        result = users_collection.insert_one(user)
        token = generate_token(result.inserted_id)
        return (
            jsonify(
                {
                    "user_id": str(result.inserted_id),
                    "name": data["name"],
                    "email": data["email"],
                    "token": token,
                    "login_methods": ["email"],
                }
            ),
            200,
        )
    except Exception as e:
        print(f"❌ Register: {e}")
        return jsonify({"error": "Registration failed"}), 500


@auth_bp.route("/login", methods=["POST"])
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
        if not bcrypt.checkpw(data["password"].encode("utf-8"), user["password"]):
            return jsonify({"error": "Invalid email or password"}), 401
        login_methods = user.get("login_methods", [])
        if "email" not in login_methods:
            login_methods.append("email")
            users_collection.update_one({"_id": user["_id"]}, {"$set": {"login_methods": login_methods}})
        token = generate_token(user["_id"])
        return (
            jsonify(
                {
                    "user_id": str(user["_id"]),
                    "name": user["name"],
                    "email": user["email"],
                    "token": token,
                    "login_methods": login_methods,
                }
            ),
            200,
        )
    except Exception as e:
        print(f"❌ Login: {e}")
        return jsonify({"error": "Login failed"}), 500


# ── Email / Verification ──


@auth_bp.route("/reset_password", methods=["POST"])
def reset_password():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Empty request"}), 400
    email = data.get("email")
    new_password = data.get("new_password")
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


@auth_bp.route("/send_password_reset_code", methods=["POST"])
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
        to_email=email,
        subject="NutriCam Password Reset Code",
        html_body=f"<p>Your reset code:</p><h2 style='color:#28a745;'>{code}</h2><p>Expires in 5 min.</p>",
        text_body=f"Your NutriCam reset code: {code}. Valid 5 minutes.",
    )
    return jsonify({"status": "ok"} if success else {"error": "Failed to send email"}), 200 if success else 500


@auth_bp.route("/send_verification", methods=["POST"])
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


@auth_bp.route("/verify_code", methods=["POST"])
def verify_code():
    data = request.get_json()
    email = data.get("email")
    code = data.get("code")
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


@auth_bp.route("/apple_login", methods=["POST"])
@db_required
def apple_login():
    try:
        data = request.get_json() or {}
        identity_token = data.get("identityToken")
        token_email = data.get("email")
        known_email = data.get("known_email")
        print_identity_token_payload(identity_token)
        if not identity_token:
            return jsonify({"error": "Missing identityToken"}), 400
        try:
            payload = verify_apple_identity_token(identity_token)
            apple_sub = payload["sub"]
        except Exception:
            return jsonify({"error": "Invalid Apple identityToken"}), 401
        user, response_email, login_methods = resolve_apple_login(
            apple_sub,
            token_email,
            known_email,
            data.get("name", "Apple User"),
        )
        token = generate_token(user["_id"])
        return (
            jsonify(
                {
                    "user_id": str(user["_id"]),
                    "name": user.get("name", "Apple User"),
                    "email": response_email,
                    "token": token,
                    "login_methods": login_methods,
                }
            ),
            200,
        )
    except Exception as e:
        print(f"❌ Apple login: {e}")
        return jsonify({"error": "Apple login failed"}), 500


@auth_bp.route("/google_login", methods=["POST"])
@db_required
def google_login():
    try:
        data = request.get_json() or {}
        google_token = data.get("idToken")
        if not google_token:
            return jsonify({"error": "Missing idToken"}), 400
        try:
            idinfo = verify_google_id_token(google_token)
            google_sub = idinfo["sub"]
            token_email = idinfo.get("email") or data.get("email")
            name = data.get("name", idinfo.get("name", "Google User"))
        except Exception:
            return jsonify({"error": "Invalid Google identityToken"}), 401
        known_email = data.get("known_email")
        user, response_email, login_methods = resolve_google_login(
            google_sub,
            token_email,
            known_email,
            name,
        )
        token = generate_token(user["_id"])
        return (
            jsonify(
                {
                    "user_id": str(user["_id"]),
                    "name": user.get("name", name),
                    "email": response_email,
                    "token": token,
                    "login_methods": login_methods,
                }
            ),
            200,
        )
    except Exception as e:
        print(f"❌ Google login: {e}")
        return jsonify({"error": "Google login failed"}), 500


# ── Account Management ──


@auth_bp.route("/delete_account", methods=["DELETE"])
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
        return (
            jsonify(
                {
                    "message": "Account deleted",
                    "deleted_data": results,
                    "timestamp": datetime.now().isoformat(),
                }
            ),
            200,
        )
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": "Deletion failed", "details": str(e)}), 500


@auth_bp.route("/update_name", methods=["POST"])
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


@auth_bp.route("/get-login-methods", methods=["GET"])
@token_required
@db_required
def get_login_methods():
    try:
        user = users_collection.find_one({"_id": ObjectId(request.user_id)})
        if not user:
            return jsonify({"error": "User not found"}), 404
        return (
            jsonify(
                {
                    "email": user.get("email", ""),
                    "login_methods": user.get("login_methods", []),
                    "has_password": "password" in user and user["password"] is not None,
                }
            ),
            200,
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@auth_bp.route("/link-email-password", methods=["POST"])
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
        hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
        methods = user.get("login_methods", [])
        if "email" not in methods:
            methods.append("email")
        users_collection.update_one({"_id": ObjectId(request.user_id)}, {"$set": {"password": hashed, "login_methods": methods}})
        return jsonify({"success": True, "login_methods": methods}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

