"""
LangGraph pipeline: health_plan_pipeline

Nodes: load_profile → analyze_history → generate_plan → format_output
"""

from __future__ import annotations

import json
import traceback
import uuid
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from execution_trace import init_trace, set_request_id, trace_node
from meal_analyzer import analyze_meal_history
from observability import (
    clear_active_trace_id,
    flush_langfuse,
    get_langfuse_client,
    lf_generation,
    lf_node_span,
    lf_trace,
    redact_for_trace,
    set_active_trace_id,
    GEMINI_MODEL_NAME,
)


class HealthPlanState(TypedDict, total=False):
    request_id: str
    profile: dict[str, Any]
    goals: list[str]
    meal_history: list[dict[str, Any]]
    gemini_model: Any
    meal_analysis: dict[str, Any]
    prompt: str
    raw_response: str
    result: dict[str, Any]
    error: str


def _fmt_gaps(gap_list: list[dict[str, Any]]) -> str:
    if not gap_list:
        return "None detected"
    return "\n".join(
        [
            f"  - {g['nutrient'].upper()}: avg {g['avg_daily']} "
            f"(reference {g['reference']}, only {int(g['ratio'] * 100)}% of target)"
            for g in gap_list
        ]
    )


def _build_health_report_prompt(profile: dict, goals: list, meal_analysis: dict) -> str:
    meal_summary = meal_analysis["summary_text"]
    height_m = profile.get("height_cm", 170) / 100
    weight = profile.get("weight_kg", 70)
    bmi = round(weight / (height_m**2), 1) if height_m > 0 else 0
    dietary_prefs = ", ".join(profile.get("dietary_preferences", [])) or "None"
    allergens = ", ".join(profile.get("allergens", [])) or "None"

    gaps = meal_analysis["nutrient_gaps"]
    deficient = gaps.get("deficient", [])
    excessive = gaps.get("excessive", [])
    recent_avgs = meal_analysis["nutrient_averages"].get("recent", {})
    top_foods = [f["food"] for f in meal_analysis["frequent_foods"][:6]]
    cooking_prefs = meal_analysis["cooking_style_prefs"]
    top_cooking = sorted(cooking_prefs.items(), key=lambda x: x[1], reverse=True)[:2]
    cooking_str = ", ".join([f"{s}({int(p * 100)}%)" for s, p in top_cooking]) or "unknown"

    clinical_flags = []
    sys_bp = profile.get("systolic_bp")
    dia_bp = profile.get("diastolic_bp")
    if sys_bp and dia_bp:
        if sys_bp >= 140 or dia_bp >= 90:
            clinical_flags.append(
                f"HIGH BLOOD PRESSURE ({sys_bp}/{dia_bp} mmHg) → "
                f"recommend LOW-SODIUM (<1500mg/day) and HIGH-POTASSIUM foods"
            )
        elif sys_bp >= 130:
            clinical_flags.append(
                f"BORDERLINE BP ({sys_bp}/{dia_bp} mmHg) → "
                f"recommend DASH-diet foods: leafy greens, berries, whole grains"
            )

    bgs = profile.get("fasting_blood_sugar")
    if bgs:
        if bgs >= 7.0:
            clinical_flags.append(
                f"HIGH FASTING BLOOD SUGAR ({bgs} mmol/L) → "
                f"recommend LOW-GI foods only: legumes, non-starchy vegetables, whole oats"
            )
        elif bgs >= 5.6:
            clinical_flags.append(
                f"BORDERLINE BLOOD SUGAR ({bgs} mmol/L) → "
                f"reduce refined carbs, recommend fiber-rich foods"
            )

    chol = profile.get("total_cholesterol")
    if chol:
        if chol >= 6.2:
            clinical_flags.append(
                f"HIGH CHOLESTEROL ({chol} mmol/L) → "
                f"recommend Omega-3 rich foods, avoid saturated fats"
            )
        elif chol >= 5.2:
            clinical_flags.append(
                f"BORDERLINE CHOLESTEROL ({chol} mmol/L) → "
                f"recommend oats, avocado, fatty fish"
            )

    if bmi >= 30:
        clinical_flags.append(f"OBESE (BMI {bmi}) → recommend HIGH-SATIETY LOW-CALORIE-DENSITY foods")
    elif bmi >= 25:
        clinical_flags.append(f"OVERWEIGHT (BMI {bmi}) → recommend lean protein and fiber-rich foods for satiety")
    elif bmi < 18.5:
        clinical_flags.append(f"UNDERWEIGHT (BMI {bmi}) → recommend calorie-dense nutrient-rich foods")

    clinical_str = (
        "\n".join([f"  • {f}" for f in clinical_flags])
        if clinical_flags
        else "  • All clinical markers within normal range"
    )

    return f"""You are a clinical nutritionist. Generate a personalized health report.

=== HARD CONSTRAINTS (never violate) ===
Allergens to EXCLUDE: {allergens}
Dietary preference: {dietary_prefs}
→ Every recommended food MUST comply with these. No exceptions.

=== CLINICAL FLAGS (pre-analyzed — trust these) ===
{clinical_str}

=== MEAL HISTORY (3-tier weighted analysis) ===
{meal_summary}

=== STRUCTURED NUTRIENT GAPS (use these exact numbers in your reasons) ===
DEFICIENCIES (below 70% of daily reference):
{_fmt_gaps(deficient)}

EXCESSES (above 130% of daily reference):
{_fmt_gaps(excessive)}

Recent daily averages: calories={recent_avgs.get('calories','N/A')} kcal | protein={recent_avgs.get('protein','N/A')}g | fiber={recent_avgs.get('fiber','N/A')}g | sodium={recent_avgs.get('sodium','N/A')}mg

=== USER CONTEXT ===
Age: {profile.get('age')} | Sex: {profile.get('sex')} | BMI: {bmi}
Goals: {', '.join(goals) if goals else 'general wellness'}
Top frequent foods: {', '.join(top_foods) if top_foods else 'no data'}
Preferred cooking styles: {cooking_str}

=== FOOD RECOMMENDATION RULES (strictly follow priority order) ===

PRIORITY 1 — Clinical flags (if any flagged above):
→ At least 1 food per clinical flag. Must directly address the flagged condition.
→ Use the specific value in the reason: e.g. "Your BP is 145/92 mmHg..."

PRIORITY 2 — Nutrient deficiencies (if any flagged above):
→ At least 1 food per deficiency. Reference the exact numbers.

PRIORITY 3 — Fit user's existing taste/cooking style:
→ Dish ideas must match cooking style: {cooking_str}

PRIORITY 4 — Fill remaining slots with balance foods.

=== OUTPUT ===
Return ONLY valid JSON, no markdown:
{{
  "health_score": <integer 0-100>,
  "health_summary": "<2-3 sentences referencing actual eating patterns and specific numbers>",
  "status_badge": "<Excellent|Good|Fair|Needs Attention>",
  "daily_calories": <integer>,
  "protein_g": <integer>,
  "carbs_g": <integer>,
  "fat_g": <integer>,
  "fiber_g": <integer>,
  "sodium_mg": <integer>,
  "weekly_calories": <integer>,
  "attention_items": [
    {{
      "metric": "<name>",
      "current_value": "<value with unit>",
      "status": "<normal|borderline|high|low>",
      "advice": "<specific actionable advice with numbers>"
    }}
  ],
  "recommended_foods": [
    {{
      "food": "<food name>",
      "reason": "<specific reason with actual numbers from above data>",
      "analysis_basis": "<clinical_marker|nutrition_gap|meal_history_pattern|general_health>",
      "dishes": ["<dish 1>", "<dish 2>", "<dish 3>"]
    }}
  ],
  "foods_to_limit": ["<food 1>", "<food 2>", "<food 3>"],
  "lifestyle_tip": "<specific tip based on user's actual patterns, not generic>"
}}

Constraints:
- recommended_foods: exactly 6 items
- attention_items: 2-5 items, omit metrics with N/A data
- dishes: must suit user's preferred cooking style ({cooking_str})
- foods_to_limit: based on what user actually eats frequently, not generic advice
- If meal data coverage < 30%, acknowledge limited data in health_summary
"""


def load_profile_node(state: HealthPlanState) -> HealthPlanState:
    rid = state["request_id"]
    with lf_node_span("health_plan.node.load_profile", redact_for_trace(state)):
        with trace_node(rid, "load_profile", input_summary=f"goals={len(state.get('goals') or [])}") as meta:
            profile = state.get("profile") or {}
            if not profile:
                err = "Profile missing"
                meta["output_summary"] = err
                return {**state, "error": err}
            meta["output_summary"] = f"Loaded profile age={profile.get('age')} sex={profile.get('sex')}"
            return {**state, "error": ""}


def analyze_history_node(state: HealthPlanState) -> HealthPlanState:
    if state.get("error"):
        return state

    rid = state["request_id"]
    with lf_node_span("health_plan.node.analyze_history", {"meals": len(state.get("meal_history") or [])}):
        with trace_node(rid, "analyze_history", input_summary=f"meals={len(state.get('meal_history') or [])}") as meta:
            meal_analysis = analyze_meal_history(state.get("meal_history") or [])
            prompt = _build_health_report_prompt(state.get("profile") or {}, state.get("goals") or [], meal_analysis)
            meta["output_summary"] = (
                f"coverage={meal_analysis.get('data_coverage')} foods={len(meal_analysis.get('frequent_foods') or [])}"
            )
            return {**state, "meal_analysis": meal_analysis, "prompt": prompt, "error": ""}


def generate_plan_node(state: HealthPlanState) -> HealthPlanState:
    if state.get("error"):
        return state

    rid = state["request_id"]
    model = state.get("gemini_model")
    with lf_node_span("health_plan.node.generate_plan", {"prompt_len": len(state.get("prompt") or "")}):
        with trace_node(rid, "generate_plan", input_summary="Gemini health report") as meta:
            if not model:
                err = "Gemini model not configured"
                meta["output_summary"] = err
                return {**state, "error": err}

            response = lf_generation(
                "health_plan.generate_plan.generate_content",
                {"prompt_excerpt": (state.get("prompt") or "")[:800]},
                lambda: model.generate_content(state["prompt"]),
                model=GEMINI_MODEL_NAME,
            )
            raw = (getattr(response, "text", None) or "").strip()
            meta["output_summary"] = raw[:200] if raw else "empty"
            return {**state, "raw_response": raw, "error": ""}


def format_output_node(state: HealthPlanState) -> HealthPlanState:
    if state.get("error"):
        return state

    rid = state["request_id"]
    with lf_node_span("health_plan.node.format_output", {"raw_len": len(state.get("raw_response") or "")}):
        with trace_node(rid, "format_output", input_summary="parse JSON") as meta:
            raw = (state.get("raw_response") or "").replace("```json", "").replace("```", "").strip()
            start = raw.find("{")
            end = raw.rfind("}") + 1
            if start >= 0 and end > start:
                raw = raw[start:end]

            try:
                result = json.loads(raw)
            except json.JSONDecodeError as exc:
                meta["output_summary"] = str(exc)
                return {**state, "error": str(exc)}

            defaults = {
                "health_score": 70,
                "health_summary": "Health analysis complete.",
                "status_badge": "Good",
                "daily_calories": 2000,
                "protein_g": 100,
                "carbs_g": 250,
                "fat_g": 65,
                "fiber_g": 25,
                "sodium_mg": 2300,
                "attention_items": [],
                "recommended_foods": [],
                "foods_to_limit": [],
                "lifestyle_tip": "Stay consistent with your healthy habits.",
            }
            for key, value in defaults.items():
                result.setdefault(key, value)

            meal_analysis = state.get("meal_analysis") or {}
            top_foods = [f["food"] for f in meal_analysis.get("frequent_foods", [])[:6]]
            result["weekly_calories"] = result.get("weekly_calories", result["daily_calories"] * 7)
            result["meal_analysis_meta"] = {
                "has_meal_data": len(meal_analysis.get("frequent_foods") or []) > 0,
                "data_coverage": meal_analysis.get("data_coverage"),
                "top_foods": top_foods,
                "nutrient_gaps": meal_analysis.get("nutrient_gaps"),
            }

            meta["output_summary"] = f"score={result.get('health_score')} cal={result.get('daily_calories')}"
            return {**state, "result": result, "error": ""}


def build_health_plan_graph():
    graph = StateGraph(HealthPlanState)
    graph.add_node("load_profile", load_profile_node)
    graph.add_node("analyze_history", analyze_history_node)
    graph.add_node("generate_plan", generate_plan_node)
    graph.add_node("format_output", format_output_node)
    graph.add_edge(START, "load_profile")
    graph.add_edge("load_profile", "analyze_history")
    graph.add_edge("analyze_history", "generate_plan")
    graph.add_edge("generate_plan", "format_output")
    graph.add_edge("format_output", END)
    return graph.compile()


def run_health_plan_pipeline(
    profile: dict,
    goals: list,
    meal_history: list | None = None,
    gemini_model=None,
    request_id: str | None = None,
) -> dict[str, Any]:
    rid = (request_id or "").strip() or str(uuid.uuid4())
    init_trace(rid)
    set_request_id(rid)

    initial: HealthPlanState = {
        "request_id": rid,
        "profile": profile,
        "goals": goals or [],
        "meal_history": meal_history or [],
        "gemini_model": gemini_model,
    }

    lf = get_langfuse_client()
    try:
        if lf:
            trace_id = lf.create_trace_id()
            set_active_trace_id(trace_id)
            with lf_trace("health_plan_pipeline", redact_for_trace(initial)):
                final = build_health_plan_graph().invoke(initial)
        else:
            final = build_health_plan_graph().invoke(initial)

        if final.get("error") and not final.get("result"):
            raise json.JSONDecodeError(final["error"], final.get("raw_response") or "", 0)
        return dict(final.get("result") or {})
    except json.JSONDecodeError:
        raise
    except Exception as exc:
        print(f"❌ health_plan_pipeline: {exc}")
        traceback.print_exc()
        raise
    finally:
        set_request_id(None)
        clear_active_trace_id()
        flush_langfuse()
