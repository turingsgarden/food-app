"""
Daily Health Coach — Gemini-powered daily plan + chat.

Uses Gemini 2.5 Flash by default; falls back to 1.5 Flash on quota errors.
"""

import json
import os
import traceback
from datetime import datetime

import google.generativeai as genai
from dotenv import load_dotenv

from meal_analyzer import analyze_meal_history

load_dotenv()

GEN_API_KEY = os.getenv("GEMINI_API_KEY")
PRIMARY_MODEL = "gemini-2.5-flash"
FALLBACK_MODEL = "gemini-1.5-flash"

if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
else:
    print("⚠️ daily_tip_pipeline: GEMINI_API_KEY not set")


def _generate_content(prompt: str, gemini_model=None) -> str:
    """Call Gemini with 2.5 Flash; on quota/rate-limit, retry with 1.5 Flash."""
    if gemini_model is not None:
        return gemini_model.generate_content(prompt).text

    if not GEN_API_KEY:
        raise Exception("Gemini API key not configured")

    models_to_try = [PRIMARY_MODEL, FALLBACK_MODEL]
    last_error = None

    for model_name in models_to_try:
        try:
            model = genai.GenerativeModel(model_name)
            print(f"🤖 daily_tip_pipeline using {model_name}")
            return model.generate_content(prompt).text
        except Exception as e:
            last_error = e
            msg = str(e).lower()
            is_quota = any(k in msg for k in ("quota", "429", "resource exhausted", "rate limit"))
            if is_quota and model_name != FALLBACK_MODEL:
                print(f"⚠️ {model_name} quota/rate limit — trying {FALLBACK_MODEL}")
                continue
            raise

    raise last_error or Exception("Gemini generation failed")


def _extract_json_object(text: str) -> dict:
    raw = text.strip().replace("```json", "").replace("```", "").strip()
    start = raw.find("{")
    end = raw.rfind("}") + 1
    if start >= 0 and end > start:
        raw = raw[start:end]
    return json.loads(raw)


def _time_of_day_label() -> str:
    hour = datetime.now().hour
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    return "evening"


def generate_daily_tip(
    profile: dict,
    goals: list,
    health_report,
    meal_history,
    date_key: str,
    gemini_model=None,
) -> dict:
    """AI-generated daily tip with comprehensive plan. No hardcoded medical copy."""
    meal_analysis = analyze_meal_history(meal_history or [])
    meal_summary = meal_analysis.get("summary_text", "No recent meal data.")
    time_slot = _time_of_day_label()

    height_m = profile.get("height_cm", 170) / 100
    weight = profile.get("weight_kg", 70)
    bmi = round(weight / (height_m ** 2), 1) if height_m > 0 else 0

    report_summary = (health_report or {}).get("health_summary", "")
    lifestyle_tip = (health_report or {}).get("lifestyle_tip", "")
    attention_items = (health_report or {}).get("attention_items", [])

    prompt = f"""You are NutriCam AI Health Coach. Generate ONE personalized daily health plan for {date_key} ({time_slot}).

Patient profile:
- Age: {profile.get('age', 'N/A')} | Sex: {profile.get('sex', 'N/A')} | BMI: {bmi}
- Systolic BP: {profile.get('systolic_bp', 'N/A')} | Diastolic BP: {profile.get('diastolic_bp', 'N/A')}
- Fasting blood sugar: {profile.get('fasting_blood_sugar', 'N/A')} mmol/L
- Total cholesterol: {profile.get('total_cholesterol', 'N/A')} mmol/L
- Dietary preferences: {', '.join(profile.get('dietary_preferences', []) or ['none'])}
- Allergens: {', '.join(profile.get('allergens', []) or ['none'])}
- Health goals: {', '.join(goals) if goals else 'general wellness'}

Health report summary: {report_summary or 'N/A'}
Report lifestyle tip: {lifestyle_tip or 'N/A'}
Attention items (from clinical report): {json.dumps(attention_items, ensure_ascii=False)}

Recent eating patterns:
{meal_summary}

INSTRUCTIONS:
1. Review ALL abnormal metrics together — do NOT use a fixed priority order.
2. Dynamically decide today's PRIMARY focus based on severity, combinations (e.g. three highs / metabolic risk), goals, time of day, and meal patterns.
3. Write actionable, specific guidance referencing actual numbers where available.
4. Return ONLY valid JSON, no markdown, no chain-of-thought text.

JSON schema:
{{
  "id": "{date_key}_<category>",
  "category": "<sodium|cholesterol|bloodSugar|weight|fiber|hydration|general>",
  "category_label": "<short human label>",
  "short_text": "<one scannable sentence for home banner>",
  "detail_text": "<2-3 sentences expanding today's action for {time_slot}>",
  "why_this_matters": "<why this priority was chosen today>",
  "suggested_action": null,
  "icon_system_name": "<SF Symbol name e.g. heart.fill, drop.fill>",
  "chat_seed": "<friendly opening message for health coach chat>",
  "comprehensive": {{
    "abnormal_evidence": [
      {{
        "id": "<stable slug e.g. fasting_blood_sugar>",
        "metric": "<name>",
        "status": "<normal|borderline|high|low|elevated>",
        "current_value": "<value with unit>",
        "advice": "<specific advice>"
      }}
    ],
    "pattern": "<threeHighs|metabolicPair|multipleMetrics|singleFocus|generalWellness>",
    "association_summary": "<how flagged metrics relate, e.g. metabolic syndrome / three highs>",
    "diet_steps": ["<step 1>", "<step 2>", "<step 3>"],
    "lifestyle_steps": ["<step 1>", "<step 2>"],
    "report_summary": "<optional excerpt or null>",
    "per_metric_plans": [
      {{
        "id": "<same as evidence id>",
        "metric": "<name>",
        "summary": "<personalized summary for this metric>",
        "diet_steps": ["<step>", "<step>"],
        "lifestyle_steps": ["<step>"]
      }}
    ]
  }}
}}

Rules:
- abnormal_evidence: include ALL non-normal attention items; if report empty, infer from profile vitals.
- per_metric_plans: one entry per abnormal_evidence item with tailored steps.
- diet_steps / lifestyle_steps: 3-5 items each for overall plan.
- Be concise, warm, and clinically cautious (not diagnostic)."""

    print(f"🧠 Generating AI daily tip | date={date_key} | time={time_slot}")
    response_text = _generate_content(prompt, gemini_model=gemini_model)
    result = _extract_json_object(response_text)

    defaults = {
        "id": f"{date_key}_general",
        "category": "general",
        "category_label": "Daily Tip",
        "short_text": "Review your health plan for today.",
        "detail_text": "Open Tell me more for personalized guidance.",
        "why_this_matters": "",
        "suggested_action": None,
        "icon_system_name": "sparkles",
        "chat_seed": "Ask me anything about your health plan today.",
        "comprehensive": {
            "abnormal_evidence": [],
            "pattern": "generalWellness",
            "association_summary": "",
            "diet_steps": [],
            "lifestyle_steps": [],
            "report_summary": report_summary or None,
            "per_metric_plans": [],
        },
    }
    for key, value in defaults.items():
        result.setdefault(key, value)

    comp = result.get("comprehensive") or {}
    for key, value in defaults["comprehensive"].items():
        comp.setdefault(key, value)
    result["comprehensive"] = comp
    result["id"] = result.get("id") or f"{date_key}_{result.get('category', 'general')}"

    print(f"✅ AI daily tip | category={result.get('category')} | id={result.get('id')}")
    return result


def daily_tip_chat_reply(
    messages: list,
    tip_snapshot: dict,
    profile: dict,
    health_report,
    gemini_model=None,
) -> str:
    """Multi-turn health coach reply grounded in the daily tip snapshot."""
    history_lines = []
    for msg in messages[-12:]:
        role = msg.get("role", "user")
        text = msg.get("text", "")
        if text:
            history_lines.append(f"{role.upper()}: {text}")

    prompt = f"""You are NutriCam AI Health Coach. Reply in plain text (no JSON, no markdown fences).

Today's plan snapshot:
{json.dumps(tip_snapshot, ensure_ascii=False)}

Patient profile (summary): age {profile.get('age', '?')}, sex {profile.get('sex', '?')}, BMI context in report.

Health report summary: {(health_report or {}).get('health_summary', 'N/A')}

Conversation:
{chr(10).join(history_lines)}

Reply as the coach: concise (2-5 sentences unless user asks for steps), actionable, reference the user's metrics when relevant. Do not reveal hidden reasoning."""

    response_text = _generate_content(prompt, gemini_model=gemini_model)
    return response_text.strip()
