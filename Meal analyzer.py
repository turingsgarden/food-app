# meal_analyzer.py
# Standalone meal history analysis module.
# Uses a 3-tier time window with decay weights to feed generate_health_report()
# in health_pipeline.py with structured dietary insights.

from datetime import datetime, timedelta
from collections import defaultdict
import re


# ── Time window configuration ─────────────────────────────────────────────────
# recent:   captures current nutritional state and short-term deficits
# medium:   captures stable dietary preferences
# longterm: captures deep food preferences (what the user consistently likes/avoids)
TIME_WINDOWS = {
    "recent":   {"days": 7,  "weight": 1.0, "label": "last 7 days"},
    "medium":   {"days": 30, "weight": 0.5, "label": "last 30 days"},
    "longterm": {"days": 90, "weight": 0.2, "label": "last 90 days"},
}

# Keywords used to identify macro/micronutrients in nutrition_info strings
NUTRIENT_KEYWORDS = {
    "protein":  ["protein", "g"],
    "carbs":    ["carbohydrate", "carb", "g"],
    "fat":      ["fat", "g"],
    "fiber":    ["fiber", "fibre", "g"],
    "sodium":   ["sodium", "mg"],
    "sugar":    ["sugar", "g"],
    "calories": ["calorie", "kcal"],
}

# Keywords used to infer cooking style from dish names and descriptions
COOKING_STYLES = {
    "fried":    ["fried", "crispy", "deep-fried", "pan-fried"],
    "grilled":  ["grilled", "bbq", "barbecue", "charred"],
    "steamed":  ["steamed", "boiled", "poached"],
    "raw":      ["salad", "raw", "fresh", "sashimi"],
    "baked":    ["baked", "roasted", "oven"],
    "stir-fry": ["stir-fry", "stir fry", "wok", "sauteed"],
}

# Keywords used to classify meals into broad food categories
FOOD_CATEGORIES = {
    "red_meat":   ["beef", "pork", "lamb", "steak", "burger", "bacon"],
    "poultry":    ["chicken", "turkey", "duck", "poultry"],
    "seafood":    ["salmon", "fish", "shrimp", "tuna", "seafood", "sushi"],
    "vegetables": ["vegetable", "salad", "broccoli", "spinach", "kale", "carrot"],
    "fruits":     ["fruit", "apple", "banana", "berry", "orange", "mango"],
    "dairy":      ["cheese", "milk", "yogurt", "cream", "dairy"],
    "grains":     ["rice", "pasta", "bread", "noodle", "wheat", "oat"],
    "legumes":    ["bean", "lentil", "tofu", "chickpea", "soy"],
    "processed":  ["fast food", "chips", "pizza", "hotdog", "processed"],
    "sweets":     ["cake", "cookie", "dessert", "ice cream", "chocolate", "sweet"],
}

# Reference daily intake values used to identify deficiencies and excesses
REFERENCE_DAILY = {
    "calories": 2000,
    "protein":  50,    # g — commonly deficient
    "carbs":    275,   # g
    "fat":      78,    # g
    "fiber":    28,    # g — most commonly deficient
    "sodium":   2300,  # mg — commonly excessive
    "sugar":    50,    # g — commonly excessive
}


# ── Main entry point ──────────────────────────────────────────────────────────

def analyze_meal_history(meals: list) -> dict:
    """
    Analyze a user's meal history and return structured dietary insights.

    Parameters:
        meals: list of meal dicts from the MongoDB 'meals' collection.
               Each entry should contain: saved_at, dish_prediction,
               image_description, nutrition_info.

    Returns a dict with:
        food_preferences      Top weighted frequent foods
        cooking_style_prefs   Detected cooking style preferences
        nutrient_averages     Per-day average nutrients across time windows
        nutrient_gaps         Identified deficiencies and excesses
        frequent_foods        All foods with weighted scores
        avoided_categories    Food categories absent from long-term history
        summary_text          Pre-formatted text to embed directly in Gemini prompt
        data_coverage         Days with recorded meals per time window
    """
    if not meals:
        return _empty_analysis()

    now = datetime.now()

    # Step 1: Bucket meals into time windows with decay weights
    windowed = _bucket_by_window(meals, now)

    # Step 2: Frequency analysis
    food_freq     = _analyze_food_frequency(windowed)
    cooking_freq  = _analyze_cooking_styles(windowed)
    category_freq = _analyze_food_categories(windowed)

    # Step 3: Weighted average nutrient intake per time window
    nutrient_avgs = _analyze_nutrients(windowed)

    # Step 4: Identify nutrient gaps and missing food categories
    gaps = _identify_gaps(nutrient_avgs, category_freq)

    # Step 5: Calculate data coverage (how many days have logged meals)
    coverage = _calculate_coverage(meals, now)

    # Step 6: Build the summary text to embed in the Gemini prompt
    summary = _build_summary_text(
        food_freq, cooking_freq, category_freq,
        nutrient_avgs, gaps, coverage
    )

    return {
        "food_preferences":    food_freq[:10],
        "cooking_style_prefs": cooking_freq,
        "nutrient_averages":   nutrient_avgs,
        "nutrient_gaps":       gaps,
        "frequent_foods":      food_freq,
        "avoided_categories":  gaps.get("missing_categories", []),
        "summary_text":        summary,
        "data_coverage":       coverage,
    }


# ── Time window bucketing ─────────────────────────────────────────────────────

def _bucket_by_window(meals: list, now: datetime) -> dict:
    """
    Sort meals into time-window buckets.
    A single meal can appear in multiple buckets (with different weights).
    """
    buckets = {key: [] for key in TIME_WINDOWS}

    for meal in meals:
        meal_date = _parse_date(meal.get("saved_at", ""))
        if not meal_date:
            continue

        days_ago = (now - meal_date).days

        for window_key, config in TIME_WINDOWS.items():
            if days_ago <= config["days"]:
                buckets[window_key].append({
                    "meal":     meal,
                    "weight":   config["weight"],
                    "days_ago": days_ago,
                })

    return buckets


# ── Food frequency analysis ───────────────────────────────────────────────────

def _analyze_food_frequency(windowed: dict) -> list:
    """
    Compute a weighted frequency score for each dish.
    More recent meals contribute higher scores due to window weights.
    """
    scores = defaultdict(float)

    for window_key, entries in windowed.items():
        weight = TIME_WINDOWS[window_key]["weight"]
        for entry in entries:
            meal = entry["meal"]
            dish = meal.get("dish_prediction", "").strip()
            if dish:
                dish_clean = dish.lower().replace("stir-fried", "stir fry")
                scores[dish_clean] += weight

    sorted_foods = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    return [{"food": f, "weighted_score": round(s, 2)} for f, s in sorted_foods]


# ── Cooking style analysis ────────────────────────────────────────────────────

def _analyze_cooking_styles(windowed: dict) -> dict:
    """
    Detect preferred cooking styles by scanning dish names and descriptions.
    Returns a proportion score per style (0.0 to 1.0).
    """
    style_scores  = defaultdict(float)
    total_weight  = 0

    for window_key, entries in windowed.items():
        weight = TIME_WINDOWS[window_key]["weight"]
        for entry in entries:
            meal = entry["meal"]
            text = (meal.get("dish_prediction", "") + " " +
                    meal.get("image_description", "")).lower()
            total_weight += weight
            for style, keywords in COOKING_STYLES.items():
                if any(kw in text for kw in keywords):
                    style_scores[style] += weight

    if total_weight == 0:
        return {}

    return {
        style: round(score / total_weight, 2)
        for style, score in sorted(style_scores.items(), key=lambda x: x[1], reverse=True)
        if score > 0
    }


# ── Food category analysis ────────────────────────────────────────────────────

def _analyze_food_categories(windowed: dict) -> dict:
    """
    Measure how often each broad food category appears across all meals,
    weighted by time window decay.
    """
    category_scores = defaultdict(float)
    total_meals     = defaultdict(int)

    for window_key, entries in windowed.items():
        weight = TIME_WINDOWS[window_key]["weight"]
        for entry in entries:
            meal = entry["meal"]
            text = (meal.get("dish_prediction", "") + " " +
                    meal.get("image_description", "")).lower()
            for category, keywords in FOOD_CATEGORIES.items():
                if any(kw in text for kw in keywords):
                    category_scores[category] += weight
                    total_meals[category]     += 1

    return {
        cat: {
            "weighted_score": round(score, 2),
            "meal_count":     total_meals[cat],
        }
        for cat, score in category_scores.items()
    }


# ── Nutrient intake analysis ──────────────────────────────────────────────────

def _analyze_nutrients(windowed: dict) -> dict:
    """
    Compute estimated per-day average nutrient intake for each time window.
    Divides total intake by estimated days (meal_count / 2.5 meals per day).
    """
    window_nutrients = {}

    for window_key, entries in windowed.items():
        if not entries:
            continue

        totals     = defaultdict(float)
        meal_count = 0

        for entry in entries:
            meal      = entry["meal"]
            nutrients = _parse_nutrition_info(meal.get("nutrition_info", ""))
            if nutrients.get("calories", 0) > 0:
                for nutrient, value in nutrients.items():
                    totals[nutrient] += value
                meal_count += 1

        if meal_count == 0:
            continue

        # Estimate number of days covered (assuming ~2.5 logged meals per day on average)
        days = max(1, meal_count / 2.5)
        window_nutrients[window_key] = {
            nutrient: round(total / days, 1)
            for nutrient, total in totals.items()
        }

    return window_nutrients


def _parse_nutrition_info(nutrition_text: str) -> dict:
    """
    Parse the pipe-delimited nutrition_info string stored in the meals collection.
    Format example: 'Calories|2000|kcal\\nProtein|80|g\\nFat|65|g'
    """
    result = {}
    if not nutrition_text:
        return result

    for line in nutrition_text.split("\n"):
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 2:
            name = parts[0].lower()
            try:
                value = float(parts[1].replace(",", ""))
                if "calorie" in name or "kcal" in name:
                    result["calories"] = value
                elif "protein" in name:
                    result["protein"] = value
                elif "carb" in name:
                    result["carbs"] = value
                elif "fat" in name and "saturated" not in name:
                    result["fat"] = value
                elif "fiber" in name or "fibre" in name:
                    result["fiber"] = value
                elif "sodium" in name:
                    result["sodium"] = value
                elif "sugar" in name and "added" not in name:
                    result["sugar"] = value
            except (ValueError, IndexError):
                continue

    return result


# ── Gap identification ────────────────────────────────────────────────────────

def _identify_gaps(nutrient_avgs: dict, category_freq: dict) -> dict:
    """
    Identify nutritional deficiencies and excesses by comparing
    recent average intake against reference daily values.
    Also flags food categories that are completely absent long-term.

    Thresholds:
        deficient  = below 70% of reference
        excessive  = above 130% of reference (sodium and sugar only)
    """
    gaps = {
        "deficient":          [],
        "excessive":          [],
        "missing_categories": [],
        "notes":              [],
    }

    recent_nutrients = nutrient_avgs.get("recent", {})

    if recent_nutrients:
        for nutrient, ref_value in REFERENCE_DAILY.items():
            recent_val = recent_nutrients.get(nutrient)
            if recent_val is None:
                continue

            ratio = recent_val / ref_value

            if nutrient in ["sodium", "sugar"]:
                # Lower is better for these two
                if ratio > 1.3:
                    gaps["excessive"].append({
                        "nutrient":  nutrient,
                        "avg_daily": recent_val,
                        "reference": ref_value,
                        "ratio":     round(ratio, 2),
                        "window":    "last 7 days",
                    })
            else:
                if ratio < 0.7:
                    gaps["deficient"].append({
                        "nutrient":  nutrient,
                        "avg_daily": recent_val,
                        "reference": ref_value,
                        "ratio":     round(ratio, 2),
                        "window":    "last 7 days",
                    })

    # Flag food categories with no meaningful presence in meal history
    all_categories     = set(FOOD_CATEGORIES.keys())
    present_categories = set(
        cat for cat, data in category_freq.items()
        if data["weighted_score"] > 0.1
    )
    gaps["missing_categories"] = list(all_categories - present_categories)

    return gaps


# ── Data coverage ─────────────────────────────────────────────────────────────

def _calculate_coverage(meals: list, now: datetime) -> dict:
    """
    Count how many distinct calendar days have at least one logged meal,
    for each time window. Used to assess data reliability.
    """
    day_sets = {key: set() for key in TIME_WINDOWS}

    for meal in meals:
        meal_date = _parse_date(meal.get("saved_at", ""))
        if not meal_date:
            continue
        days_ago = (now - meal_date).days
        date_str = meal_date.strftime("%Y-%m-%d")
        for window_key, config in TIME_WINDOWS.items():
            if days_ago <= config["days"]:
                day_sets[window_key].add(date_str)

    return {
        window_key: {
            "days_with_data": len(day_sets[window_key]),
            "total_days":     config["days"],
            "coverage_pct":   round(len(day_sets[window_key]) / config["days"] * 100, 1),
        }
        for window_key, config in TIME_WINDOWS.items()
    }


# ── Prompt summary builder ────────────────────────────────────────────────────

def _build_summary_text(food_freq, cooking_freq, category_freq,
                        nutrient_avgs, gaps, coverage) -> str:
    """
    Build a pre-formatted text block to embed directly into the Gemini prompt.
    Contains all key dietary insights derived from the 3-tier analysis.
    """
    lines = []

    # Data coverage header
    r = coverage.get("recent",  {})
    m = coverage.get("medium",  {})
    lines.append(
        f"DATA COVERAGE: {r.get('days_with_data',0)}/{r.get('total_days',7)} days in last week, "
        f"{m.get('days_with_data',0)}/{m.get('total_days',30)} days in last month"
    )

    # Top frequent foods (weighted by recency)
    if food_freq:
        top_foods = [f["food"] for f in food_freq[:8]]
        lines.append(f"\nMOST FREQUENT FOODS (weighted by recency): {', '.join(top_foods)}")
    else:
        lines.append("\nMOST FREQUENT FOODS: No data")

    # Food category distribution
    if category_freq:
        present = sorted(
            [(cat, data["weighted_score"]) for cat, data in category_freq.items()],
            key=lambda x: x[1], reverse=True
        )
        present_str = ", ".join([f"{cat}({score:.1f})" for cat, score in present[:6]])
        lines.append(f"\nFOOD CATEGORY PRESENCE (weighted score): {present_str}")

        missing = gaps.get("missing_categories", [])
        if missing:
            lines.append(f"CONSISTENTLY ABSENT CATEGORIES: {', '.join(missing)}")
    else:
        lines.append("\nFOOD CATEGORIES: No data available")

    # Preferred cooking styles
    if cooking_freq:
        top_styles = sorted(cooking_freq.items(), key=lambda x: x[1], reverse=True)[:3]
        styles_str = ", ".join([f"{s}({p:.0%})" for s, p in top_styles])
        lines.append(f"\nPREFERRED COOKING STYLES: {styles_str}")

    # Nutrient intake across all three time windows
    lines.append("\nNUTRIENT INTAKE ANALYSIS (per-day averages):")
    for window_key, label in [
        ("recent",   "7-day avg"),
        ("medium",   "30-day avg"),
        ("longterm", "90-day avg"),
    ]:
        nutrients = nutrient_avgs.get(window_key, {})
        if nutrients:
            cal    = nutrients.get("calories", "N/A")
            prot   = nutrients.get("protein",  "N/A")
            fiber  = nutrients.get("fiber",    "N/A")
            sodium = nutrients.get("sodium",   "N/A")
            lines.append(
                f"  {label}: {cal} kcal | protein {prot}g | fiber {fiber}g | sodium {sodium}mg"
            )

    # Deficiencies and excesses
    deficient = gaps.get("deficient", [])
    excessive = gaps.get("excessive", [])

    if deficient:
        def_str = ", ".join([
            f"{g['nutrient']} (avg {g['avg_daily']}, ref {g['reference']})"
            for g in deficient
        ])
        lines.append(f"\nNUTRIENT DEFICIENCIES (below 70% of reference): {def_str}")

    if excessive:
        exc_str = ", ".join([
            f"{g['nutrient']} (avg {g['avg_daily']}, ref {g['reference']})"
            for g in excessive
        ])
        lines.append(f"NUTRIENTS OVER LIMIT (above 130% of reference): {exc_str}")

    if not deficient and not excessive:
        lines.append("\nNUTRIENT BALANCE: No significant deficiencies or excesses detected")

    # Weighting explanation (helps Gemini understand how to use the data)
    lines.append(
        "\nWEIGHTING NOTE: "
        "Recent (7d, w=1.0) reflects current nutritional state. "
        "Medium (30d, w=0.5) reflects stable preferences. "
        "Long-term (90d, w=0.2) reflects deep food preferences. "
        "Balance 'what they need now' against 'what they actually enjoy eating'."
    )

    return "\n".join(lines)


# ── Utilities ─────────────────────────────────────────────────────────────────

def _parse_date(date_str: str):
    """
    Parse ISO 8601 date strings, including microsecond variants
    (e.g. '2026-04-13T03:51:35.123456') produced by the Flask backend.
    """
    if not date_str:
        return None

    formats = [
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d",
    ]
    for fmt in formats:
        try:
            return datetime.strptime(date_str[:26].strip(), fmt)
        except ValueError:
            continue

    try:
        return datetime.fromisoformat(date_str.replace("Z", "+00:00").split("+")[0])
    except Exception:
        return None


def _empty_analysis() -> dict:
    """Return a safe empty analysis result when no meal history is available."""
    return {
        "food_preferences":    [],
        "cooking_style_prefs": {},
        "nutrient_averages":   {},
        "nutrient_gaps": {
            "deficient": [], "excessive": [], "missing_categories": [], "notes": []
        },
        "frequent_foods":    [],
        "avoided_categories": [],
        "summary_text": (
            "No meal history available. "
            "Recommendations will be based on health profile and dietary preferences only."
        ),
        "data_coverage": {
            w: {"days_with_data": 0, "total_days": c["days"], "coverage_pct": 0.0}
            for w, c in TIME_WINDOWS.items()
        },
    }
