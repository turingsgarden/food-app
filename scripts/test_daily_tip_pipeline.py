#!/usr/bin/env python3
"""Smoke-test daily tip JSON generation (requires GEMINI_API_KEY in env)."""

import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from daily_tip_pipeline import generate_daily_tip, daily_tip_chat_reply


def main():
    if not os.getenv("GEMINI_API_KEY"):
        print("Set GEMINI_API_KEY to run this test.")
        sys.exit(1)

    profile = {
        "age": 45,
        "sex": "male",
        "height_cm": 175,
        "weight_kg": 82,
        "systolic_bp": 142,
        "diastolic_bp": 88,
        "fasting_blood_sugar": 6.2,
        "total_cholesterol": 5.8,
        "dietary_preferences": ["low salt"],
        "allergens": [],
    }
    health_report = {
        "health_summary": "Elevated BP, borderline glucose, high cholesterol.",
        "lifestyle_tip": "Walk 15 minutes after meals.",
        "attention_items": [
            {
                "id": "systolic_bp",
                "metric": "Systolic BP",
                "status": "high",
                "current_value": "142 mmHg",
                "advice": "Reduce sodium intake.",
            },
            {
                "id": "fasting_blood_sugar",
                "metric": "Fasting Blood Sugar",
                "status": "borderline",
                "current_value": "6.2 mmol/L",
                "advice": "Pair carbs with protein.",
            },
        ],
    }
    date_key = datetime.now().strftime("%Y-%m-%d")

    print("=== generate_daily_tip ===")
    tip = generate_daily_tip(
        profile=profile,
        goals=["lower_blood_pressure", "control_blood_sugar"],
        health_report=health_report,
        meal_history=[],
        date_key=date_key,
    )
    print(json.dumps(tip, indent=2, ensure_ascii=False))

    print("\n=== daily_tip_chat_reply ===")
    messages = [
        {"role": "coach", "text": tip.get("chat_seed", "Hello")},
        {"role": "user", "text": "What should I eat tonight?"},
    ]
    reply = daily_tip_chat_reply(
        messages=messages,
        tip_snapshot=tip,
        profile=profile,
        health_report=health_report,
    )
    print(reply)


if __name__ == "__main__":
    main()
