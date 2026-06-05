"""
LangGraph pipeline: meal_photo_pipeline

Nodes: validate_image → analyze_food → parse_nutrition → validate_output
"""

from __future__ import annotations

import os
import re
import time
import traceback
import uuid
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph
from PIL import Image

from execution_trace import init_trace, set_request_id, trace_node
from extensions import gemini_model
from model_pipeline import encode_image, validate_image_for_analysis
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

MEAL_ANALYSIS_PROMPT = """Analyze this food image completely. Return ONLY the sections below, no extra text.

=== DISH NAME ===
[The specific dish name]

=== VISIBLE INGREDIENTS ===
[Each ingredient you can see, one per line:]
Ingredient name | Quantity | Unit | Visible

=== HIDDEN INGREDIENTS ===
[Ingredients used in cooking but not visible, e.g. oil, salt, stock:]
Ingredient name | Quantity | Unit | Hidden

=== NUTRITION ===
[Calculate based on ALL ingredients above:]
Calories|VALUE|kcal
Protein|VALUE|g
Fat|VALUE|g
Carbohydrates|VALUE|g
Fiber|VALUE|g
Sugar|VALUE|g
Sodium|VALUE|mg

Rules:
- Only include ingredients actually present or used
- Use realistic quantities based on portion size
- Nutrition must reflect actual ingredients listed
- No placeholder or example values
- If you cannot identify the food, write "Unable to identify" under DISH NAME"""


class MealPhotoState(TypedDict, total=False):
    request_id: str
    image_path: str
    user_id: str
    start_time: float
    image_data: str
    raw_response: str
    dish_prediction: str
    image_description: str
    hidden_ingredients: str
    nutrition_info: str
    analysis_confidence: int
    detection_stats: dict[str, Any]
    result: dict[str, Any]
    error: str


def _failure_result(user_id: str, message: str, *, dish: str = "Detection failed") -> dict[str, Any]:
    return {
        "dish_prediction": dish,
        "image_description": f"Error: {message} | 0 | items | Failed",
        "hidden_ingredients": "",
        "nutrition_info": "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
        "analysis_time": 0,
        "user_id": user_id,
        "error": message,
        "analysis_confidence": 0,
    }


def validate_image_node(state: MealPhotoState) -> MealPhotoState:
    rid = state["request_id"]
    with lf_node_span("meal_photo.node.validate_image", redact_for_trace({"image_path": state.get("image_path")})):
        with trace_node(rid, "validate_image", input_summary=f"path={state.get('image_path')}") as meta:
            image_path = state.get("image_path") or ""
            if not image_path or not os.path.exists(image_path):
                out = {**state, "error": "Image file not found", "result": _failure_result(state.get("user_id", ""), "Image file not found")}
                meta["output_summary"] = "Image missing"
                return out

            is_valid, msg = validate_image_for_analysis(image_path)
            if not is_valid:
                out = {**state, "error": msg, "result": _failure_result(state.get("user_id", ""), msg)}
                meta["output_summary"] = msg
                return out

            image = Image.open(image_path)
            image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")

            base, _ = os.path.splitext(image_path)
            optimized_path = base + "_opt.jpg"
            image.save(optimized_path, "JPEG", quality=85)
            image_data = encode_image(optimized_path)
            try:
                os.remove(optimized_path)
            except Exception:
                pass

            meta["output_summary"] = f"Validated image ({len(image_data)} b64 chars)"
            return {**state, "image_data": image_data, "error": ""}


def analyze_food_node(state: MealPhotoState) -> MealPhotoState:
    if state.get("error") or state.get("result"):
        return state

    rid = state["request_id"]
    with lf_node_span("meal_photo.node.analyze_food", {"user_id": state.get("user_id")}):
        with trace_node(rid, "analyze_food", input_summary="Gemini vision single-pass") as meta:
            if not gemini_model:
                err = "Gemini model not configured"
                meta["output_summary"] = err
                return {**state, "error": err, "result": _failure_result(state.get("user_id", ""), err)}

            response = lf_generation(
                "meal_photo.analyze_food.generate_content",
                {"prompt_excerpt": MEAL_ANALYSIS_PROMPT[:500], "multimodal": True},
                lambda: gemini_model.generate_content(
                    [MEAL_ANALYSIS_PROMPT, {"mime_type": "image/jpeg", "data": state["image_data"]}]
                ),
                model=GEMINI_MODEL_NAME,
            )
            raw = (getattr(response, "text", None) or "").strip()
            if not raw:
                err = "Empty response from Gemini"
                meta["output_summary"] = err
                return {**state, "error": err, "result": _failure_result(state.get("user_id", ""), err)}

            meta["output_summary"] = raw[:200]
            return {**state, "raw_response": raw, "error": ""}


def parse_nutrition_node(state: MealPhotoState) -> MealPhotoState:
    if state.get("error") or state.get("result"):
        return state

    rid = state["request_id"]
    raw = state.get("raw_response", "")

    with lf_node_span("meal_photo.node.parse_nutrition", {"raw_len": len(raw)}):
        with trace_node(rid, "parse_nutrition", input_summary=f"raw_len={len(raw)}") as meta:
            if "unable to identify" in raw.lower():
                start_time = state.get("start_time", time.time())
                result = {
                    "dish_prediction": "Could not identify food",
                    "image_description": "Analysis failed | 0 | items | Unable to detect",
                    "hidden_ingredients": "",
                    "nutrition_info": "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
                    "analysis_time": time.time() - start_time,
                    "user_id": state.get("user_id", ""),
                    "error": "Detection failed: unable to identify food",
                    "analysis_confidence": 0,
                }
                meta["output_summary"] = "Unable to identify food"
                return {**state, "result": result, "error": result["error"]}

            dish_name = ""
            visible_ingredients: list[str] = []
            hidden_ingredients: list[str] = []
            nutrition_lines: list[str] = []
            current_section = None

            for line in raw.split("\n"):
                line = line.strip()
                if not line:
                    continue
                clean_line = line.replace("**", "").strip()
                if "=== DISH NAME ===" in line:
                    current_section = "dish"
                elif "=== VISIBLE INGREDIENTS ===" in line:
                    current_section = "visible"
                elif "=== HIDDEN INGREDIENTS ===" in line:
                    current_section = "hidden"
                elif "=== NUTRITION ===" in line:
                    current_section = "nutrition"
                elif current_section == "dish" and not dish_name:
                    dish_name = line
                elif current_section == "visible" and "|" in line:
                    parts = line.split("|")
                    name = parts[0].strip()
                    if len(parts) >= 3 and len(name) > 1 and not any(
                        x in name.lower() for x in ["ingredient", "quantity", "---"]
                    ):
                        visible_ingredients.append(line)
                elif current_section == "hidden" and "|" in line:
                    parts = [p.strip() for p in line.split("|") if p.strip()]
                    # Skip row divider lines like ---|---|---
                    if not parts or all(c == '-' for c in parts[0]):
                        continue
                    name = parts[0]
                    if len(parts) >= 3 and len(name) > 1 and not any(
                        x in name.lower() for x in ["ingredient", "quantity", "---"]
                    ):
                        hidden_ingredients.append(line)
                elif current_section == "nutrition" and "|" in line:
                    parts = line.split("|")
                    if len(parts) >= 3:
                        nutrient = parts[0].strip()
                        value_str = re.sub(r"[^\d.]", "", parts[1].strip())
                        unit = parts[2].strip()
                        if value_str and float(value_str) >= 0:
                            nutrition_lines.append(f"{nutrient}|{value_str}|{unit}")

            required_nutrients = {
                "Calories": "kcal",
                "Protein": "g",
                "Fat": "g",
                "Carbohydrates": "g",
                "Fiber": "g",
                "Sugar": "g",
                "Sodium": "mg",
            }
            found_nutrients: dict[str, str] = {}
            for line in nutrition_lines:
                parts = line.split("|")
                if len(parts) >= 2:
                    for req in required_nutrients:
                        if req.lower() in parts[0].lower():
                            found_nutrients[req] = line
                            break

            final_nutrition = []
            for nutrient, unit in required_nutrients.items():
                if nutrient in found_nutrients:
                    final_nutrition.append(found_nutrients[nutrient])
                else:
                    final_nutrition.append(f"{nutrient}|0|{unit}")

            meta["output_summary"] = (
                f"dish={dish_name[:60]} visible={len(visible_ingredients)} hidden={len(hidden_ingredients)}"
            )
            return {
                **state,
                "dish_prediction": dish_name,
                "image_description": "\n".join(visible_ingredients),
                "hidden_ingredients": "\n".join(hidden_ingredients),
                "nutrition_info": "\n".join(final_nutrition),
                "analysis_confidence": min(100, len(visible_ingredients) * 10),
                "detection_stats": {
                    "visible_count": len(visible_ingredients),
                    "hidden_count": len(hidden_ingredients),
                    "total_ingredients": len(visible_ingredients) + len(hidden_ingredients),
                    "method": "single_pass_v3",
                },
                "_visible_count": len(visible_ingredients),
            }


def validate_output_node(state: MealPhotoState) -> MealPhotoState:
    if state.get("result"):
        return state

    rid = state["request_id"]
    with lf_node_span("meal_photo.node.validate_output", redact_for_trace(state)):
        with trace_node(rid, "validate_output", input_summary=state.get("dish_prediction", "")) as meta:
            visible_count = state.get("_visible_count", 0)
            if state.get("error"):
                meta["output_summary"] = state["error"]
                return state

            if visible_count < 2:
                err = f"Insufficient ingredients detected (only {visible_count})"
                meta["output_summary"] = err
                return {
                    **state,
                    "error": err,
                    "result": _failure_result(state.get("user_id", ""), err),
                }

            nutrition_info = state.get("nutrition_info", "")
            calories = 0
            for line in nutrition_info.split("\n"):
                if "calories" in line.lower():
                    parts = line.split("|")
                    if len(parts) >= 2:
                        try:
                            calories = float(re.sub(r"[^\d.]", "", parts[1]))
                        except ValueError:
                            calories = 0
                    break

            dish = (state.get("dish_prediction") or "").strip()
            if calories <= 0 or not dish:
                err = "Invalid analysis output"
                meta["output_summary"] = err
                return {
                    **state,
                    "error": err,
                    "result": _failure_result(state.get("user_id", ""), err),
                }

            start_time = state.get("start_time", time.time())
            analysis_time = time.time() - start_time
            result = {
                "dish_prediction": dish,
                "image_description": state.get("image_description", ""),
                "hidden_ingredients": state.get("hidden_ingredients", ""),
                "nutrition_info": nutrition_info,
                "analysis_time": analysis_time,
                "user_id": state.get("user_id", ""),
                "analysis_confidence": state.get("analysis_confidence", 0),
                "detection_stats": state.get("detection_stats", {}),
            }
            meta["output_summary"] = f"OK dish={dish[:40]} cal={calories}"
            return {**state, "result": result, "error": ""}


def build_meal_photo_graph():
    graph = StateGraph(MealPhotoState)
    graph.add_node("validate_image", validate_image_node)
    graph.add_node("analyze_food", analyze_food_node)
    graph.add_node("parse_nutrition", parse_nutrition_node)
    graph.add_node("validate_output", validate_output_node)
    graph.add_edge(START, "validate_image")
    graph.add_edge("validate_image", "analyze_food")
    graph.add_edge("analyze_food", "parse_nutrition")
    graph.add_edge("parse_nutrition", "validate_output")
    graph.add_edge("validate_output", END)
    return graph.compile()


def run_meal_photo_pipeline(
    image_path: str,
    user_id: str,
    request_id: str | None = None,
) -> dict[str, Any]:
    rid = (request_id or "").strip() or str(uuid.uuid4())
    init_trace(rid)
    set_request_id(rid)

    initial: MealPhotoState = {
        "request_id": rid,
        "image_path": image_path,
        "user_id": user_id,
        "start_time": time.time(),
    }

    lf = get_langfuse_client()
    trace_id: str | None = None
    final: MealPhotoState | None = None

    try:
        if lf:
            trace_id = lf.create_trace_id()
            set_active_trace_id(trace_id)
            with lf_trace("meal_photo_pipeline", initial):
                final = build_meal_photo_graph().invoke(initial)
        else:
            final = build_meal_photo_graph().invoke(initial)

        result = dict(final.get("result") or _failure_result(user_id, final.get("error") or "Analysis failed"))
        result["request_id"] = rid
        return result
    except Exception as exc:
        print(f"❌ meal_photo_pipeline: {exc}")
        traceback.print_exc()
        result = _failure_result(user_id, str(exc))
        result["request_id"] = rid
        return result
    finally:
        set_request_id(None)
        clear_active_trace_id()
        flush_langfuse()
