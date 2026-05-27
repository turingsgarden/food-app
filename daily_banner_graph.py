"""
LangGraph pipeline for AI-powered daily health coach banner messages.

Pipeline: load_context -> analyze_health -> generate_message -> validate_output
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime, timedelta
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from execution_trace import init_trace, set_request_id, trace_node
from extensions import db, gemini_model
from meal_analyzer import analyze_meal_history
from observability import GEMINI_MODEL_NAME, lf_generation, lf_node_span, redact_for_trace


class DailyBannerState(TypedDict, total=False):
    request_id: str
    user_id: str
    profile: dict[str, Any]
    meals: list[dict[str, Any]]
    health_report: dict[str, Any]
    signals: dict[str, Any]
    generated_message: str
    final_message: str
    error: str


def _num(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _extract_clinical_flags(profile: dict[str, Any]) -> list[str]:
    flags: list[str] = []
    sys_bp = _num(profile.get("systolic_bp"))
    dia_bp = _num(profile.get("diastolic_bp"))
    fbg = _num(profile.get("fasting_blood_sugar"))
    chol = _num(profile.get("total_cholesterol"))
    trig = _num(profile.get("triglycerides"))

    if (sys_bp is not None and sys_bp > 140) or (dia_bp is not None and dia_bp > 90):
        flags.append("bp_high")
    if fbg is not None and fbg > 6.1:
        flags.append("blood_sugar_high")
    if chol is not None and chol > 5.2:
        flags.append("cholesterol_high")
    if trig is not None and trig > 1.7:
        flags.append("triglycerides_high")
    return flags


def _time_of_day(now: datetime) -> str:
    hour = now.hour
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    return "evening"


def load_context_node(state: DailyBannerState) -> DailyBannerState:
    rid = state["request_id"]
    user_id = state.get("user_id", "")
    with lf_node_span("daily_banner.node.load_context", {"user_id": user_id}):
        with trace_node(rid, "load_context", input_summary=f"user_id={user_id}") as meta:
            profile = state.get("profile") or {}
            if not profile:
                profile = db["health_profiles"].find_one({"user_id": user_id}) or {}
            profile.pop("_id", None)

            meals = list(
                db["meals"]
                .find(
                    {
                        "user_id": user_id,
                        "saved_at": {"$gte": (datetime.now() - timedelta(days=7)).isoformat()},
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
                .limit(200)
            )

            report = db["health_reports"].find_one({"user_id": user_id}, sort=[("created_at", -1)]) or {}
            report.pop("_id", None)

            meta["output_summary"] = f"profile={bool(profile)} meals={len(meals)} report={bool(report)}"
            return {**state, "profile": profile, "meals": meals, "health_report": report, "error": ""}


def analyze_health_node(state: DailyBannerState) -> DailyBannerState:
    rid = state["request_id"]
    with lf_node_span("daily_banner.node.analyze_health", redact_for_trace(state)):
        with trace_node(rid, "analyze_health", input_summary=f"meals={len(state.get('meals') or [])}") as meta:
            profile = state.get("profile") or {}
            meals = state.get("meals") or []
            report = state.get("health_report") or {}
            analysis = analyze_meal_history(meals) if meals else {}

            gaps = (analysis.get("nutrient_gaps") or {}) if analysis else {}
            deficiencies = (gaps.get("deficient") or [])[:2]
            excesses = (gaps.get("excessive") or [])[:1]
            cooking_prefs = analysis.get("cooking_style_prefs") or {}
            dominant_style = None
            if cooking_prefs:
                dominant_style = sorted(cooking_prefs.items(), key=lambda x: x[1], reverse=True)[0][0]

            now = datetime.now()
            signals = {
                "clinical_flags": _extract_clinical_flags(profile),
                "nutrient_gaps": [g.get("nutrient", "") for g in deficiencies if g.get("nutrient")],
                "nutrient_excesses": [g.get("nutrient", "") for g in excesses if g.get("nutrient")],
                "cooking_variety": dominant_style,
                "dietary_prefs": profile.get("dietary_preferences") or [],
                "health_score": report.get("health_score"),
                "time_of_day": _time_of_day(now),
                "day_of_week": now.strftime("%A"),
            }
            meta["output_summary"] = (
                f"flags={len(signals['clinical_flags'])} gaps={len(signals['nutrient_gaps'])} "
                f"excesses={len(signals['nutrient_excesses'])}"
            )
            return {**state, "signals": signals, "error": ""}


def generate_message_node(state: DailyBannerState) -> DailyBannerState:
    rid = state["request_id"]
    with lf_node_span("daily_banner.node.generate_message", redact_for_trace(state.get("signals") or {})):
        with trace_node(rid, "generate_message", input_summary="Gemini banner sentence") as meta:
            if gemini_model is None:
                return {**state, "generated_message": "", "error": "Gemini model not configured"}

            signals = state.get("signals") or {}
            prompt = (
                "You are a warm, knowledgeable health coach. Generate exactly ONE sentence "
                "of personalized health advice for the user's daily banner.\n"
                "Rules:\n"
                "- Exactly one sentence, max 20 words\n"
                "- Warm and friendly tone, like a supportive friend\n"
                "- Specific and actionable (mention a real food, nutrient, or habit)\n"
                "- Never say 'should', 'must', 'consult', 'doctor', 'medical'\n"
                "- Vary the focus: clinical > nutrient gap > diet preference > general wellness\n"
                "- If it's morning: focus on breakfast/start of day\n"
                "- If it's evening: focus on dinner/reflection/tomorrow\n"
                "- Never repeat generic advice if specific data is available\n\n"
                "Generate a daily health tip for this user:\n"
                f"Time: {signals.get('time_of_day')}, {signals.get('day_of_week')}\n"
                f"Clinical flags: {signals.get('clinical_flags') or 'none'}\n"
                f"Nutrient gaps this week: {signals.get('nutrient_gaps') or 'none'}\n"
                f"Nutrient excesses: {signals.get('nutrient_excesses') or 'none'}\n"
                f"Dietary preferences: {signals.get('dietary_prefs') or 'no restrictions'}\n"
                f"Dominant cooking style: {signals.get('cooking_variety') or 'varied'}\n"
                f"Health score: {signals.get('health_score') or 'not assessed'}\n\n"
                "Return ONLY the one sentence. No preamble, no explanation."
            )

            response = lf_generation(
                "daily_banner.generate_message.generate_content",
                {"prompt_excerpt": prompt[:2000]},
                lambda: gemini_model.generate_content(prompt),
                model=GEMINI_MODEL_NAME,
            )
            text = (getattr(response, "text", None) or "").strip()
            message = text.splitlines()[0].strip() if text else ""
            meta["output_summary"] = message[:200]
            return {**state, "generated_message": message, "error": ""}


def _is_single_sentence(text: str) -> bool:
    sentence_count = len(re.findall(r"[.!?]", text))
    return sentence_count == 1 and text[-1:] in ".!?"


def validate_output_node(state: DailyBannerState) -> DailyBannerState:
    rid = state["request_id"]
    with lf_node_span("daily_banner.node.validate_output", {"message": state.get("generated_message", "")[:200]}):
        with trace_node(rid, "validate_output", input_summary="validate Gemini output") as meta:
            candidate = (state.get("generated_message") or "").strip()
            lowered = candidate.lower()
            forbidden = ("should", "must", "consult", "doctor", "medical", "diagnos")
            words = candidate.split()

            valid = bool(candidate) and 5 <= len(words) <= 25 and _is_single_sentence(candidate)
            if valid and any(token in lowered for token in forbidden):
                valid = False

            if not valid:
                from daily_banner import build_daily_banner_message

                fallback = build_daily_banner_message(
                    state.get("profile") or {},
                    None,  # fallback now avoids meal-count encouragement logic
                    state.get("user_id", ""),
                )
                meta["output_summary"] = "fallback_used"
                return {**state, "final_message": fallback, "error": ""}

            meta["output_summary"] = "validated"
            return {**state, "final_message": candidate, "error": ""}


def build_daily_banner_graph():
    graph = StateGraph(DailyBannerState)
    graph.add_node("load_context", load_context_node)
    graph.add_node("analyze_health", analyze_health_node)
    graph.add_node("generate_message", generate_message_node)
    graph.add_node("validate_output", validate_output_node)
    graph.add_edge(START, "load_context")
    graph.add_edge("load_context", "analyze_health")
    graph.add_edge("analyze_health", "generate_message")
    graph.add_edge("generate_message", "validate_output")
    graph.add_edge("validate_output", END)
    return graph.compile()


def run_daily_banner_pipeline(
    user_id: str,
    profile: dict[str, Any] | None = None,
    meals_collection: Any | None = None,  # kept for API compatibility with caller
) -> dict[str, str]:
    rid = str(uuid.uuid4())
    init_trace(rid)
    set_request_id(rid)
    try:
        initial: DailyBannerState = {
            "request_id": rid,
            "user_id": user_id,
            "profile": profile or {},
            "error": "",
        }
        final = build_daily_banner_graph().invoke(initial)
        return {"final_message": str(final.get("final_message") or ""), "request_id": rid}
    finally:
        set_request_id(None)
