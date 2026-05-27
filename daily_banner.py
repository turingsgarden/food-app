"""
Rule-based daily health coach banner message (no Gemini).

Priority: clinical flags → meal logging gap → diet tip → default fallback.
"""

from __future__ import annotations

from datetime import datetime, timedelta

DEFAULT_BANNER_MESSAGE = (
    "Start your day with a balanced breakfast — protein, healthy fat, "
    "and fiber keeps energy steady."
)

CLINICAL_MESSAGES = [
    (
        lambda p: _bp_high(p),
        "Your blood pressure reading suggests watching sodium intake today. "
        "Try steaming or grilling instead of frying.",
    ),
    (
        lambda p: _num(p.get("fasting_blood_sugar")) is not None
        and _num(p.get("fasting_blood_sugar")) > 6.1,
        "Keep blood sugar steady today — pair carbs with protein or fiber "
        "at every meal.",
    ),
    (
        lambda p: _num(p.get("total_cholesterol")) is not None
        and _num(p.get("total_cholesterol")) > 5.2,
        "Your cholesterol profile benefits from soluble fiber. "
        "Oats, legumes, and vegetables are great choices today.",
    ),
    (
        lambda p: _num(p.get("triglycerides")) is not None
        and _num(p.get("triglycerides")) > 1.7,
        "High triglycerides respond well to reducing refined carbs and sugar. "
        "Focus on whole grains today.",
    ),
]

DIET_TIPS = {
    "vegan": (
        "Great choice going plant-based! Make sure you're getting "
        "enough B12 and iron today."
    ),
    "keto": (
        "On keto today? Keep electrolytes up — sodium, potassium, "
        "and magnesium matter."
    ),
    "gluten_free": (
        "Gluten-free eating is easier with whole foods. "
        "Rice, quinoa, and potatoes are your friends."
    ),
}


def _num(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _bp_high(profile: dict) -> bool:
    sys_bp = _num(profile.get("systolic_bp"))
    dia_bp = _num(profile.get("diastolic_bp"))
    if sys_bp is None and dia_bp is None:
        return False
    return (sys_bp is not None and sys_bp > 140) or (dia_bp is not None and dia_bp > 90)


def _has_clinical_data(profile: dict) -> bool:
    return any(
        _num(profile.get(key)) is not None
        for key in (
            "systolic_bp",
            "diastolic_bp",
            "fasting_blood_sugar",
            "total_cholesterol",
            "triglycerides",
        )
    )


def _clinical_flag_message(profile: dict) -> str | None:
    if not _has_clinical_data(profile):
        return None
    for predicate, message in CLINICAL_MESSAGES:
        if predicate(profile):
            return message
    return None


def _meals_logged_last_7_days(meals_collection, user_id: str) -> int:
    if meals_collection is None:
        return 0
    cutoff = (datetime.now() - timedelta(days=7)).isoformat()
    try:
        return meals_collection.count_documents(
            {"user_id": user_id, "saved_at": {"$gte": cutoff}}
        )
    except Exception:
        return 0


def _diet_tip_message(profile: dict) -> str | None:
    prefs = {str(p).lower() for p in profile.get("dietary_preferences") or []}
    for key in ("vegan", "keto", "gluten_free"):
        if key in prefs:
            return DIET_TIPS[key]
    return None


def build_daily_banner_message(profile: dict | None, meals_collection, user_id: str) -> str:
    if not profile:
        return DEFAULT_BANNER_MESSAGE

    clinical = _clinical_flag_message(profile)
    if clinical:
        return clinical

    if _meals_logged_last_7_days(meals_collection, user_id) < 3:
        return (
            "Logging more meals helps your health coach give better advice. "
            "Try snapping your next meal!"
        )

    diet_tip = _diet_tip_message(profile)
    if diet_tip:
        return diet_tip

    return DEFAULT_BANNER_MESSAGE
