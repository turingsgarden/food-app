# health_pipeline.py

import google.generativeai as genai
import os
import re
import json
import traceback
import concurrent.futures
from datetime import datetime, timedelta
from dotenv import load_dotenv
from meal_analyzer import analyze_meal_history

load_dotenv()

GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
    _model       = genai.GenerativeModel('gemini-2.5-pro')
    _flash_model = genai.GenerativeModel('gemini-2.5-flash')
else:
    _model = _flash_model = None
    print("⚠️ health_pipeline: GEMINI_API_KEY not set")

VARIETY_HINTS = [
    "Use Asian cuisine: rice, tofu, miso, edamame, bok choy, sesame",
    "Use Mediterranean cuisine: olive oil, hummus, falafel, quinoa, feta, olives",
    "Use Mexican cuisine: beans, avocado, corn tortilla, salsa, lime, peppers",
    "Use Japanese cuisine: soba noodles, seaweed, salmon, miso soup, edamame",
    "Use Indian cuisine: lentils, chickpeas, spinach, curry, basmati rice, yogurt",
    "Use Western cuisine: whole grain bread, eggs, sweet potato, chicken, broccoli",
    "Use Middle Eastern cuisine: pita, tahini, lamb, couscous, pomegranate, mint",
]


def _get_model(gemini_model=None):
    return gemini_model or _model


# ════════════════════════════════════════════════════════════════
# 1. 生成营养目标
# ════════════════════════════════════════════════════════════════

def generate_nutrition_targets(profile: dict, goals: list, gemini_model=None) -> dict:
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    height_m = profile.get("height_cm", 170) / 100
    weight   = profile.get("weight_kg", 70)
    bmi      = round(weight / (height_m ** 2), 1)
    bp = "N/A"
    if profile.get("systolic_bp") and profile.get("diastolic_bp"):
        bp = f"{profile['systolic_bp']}/{profile['diastolic_bp']} mmHg"

    prompt = f"""You are a clinical dietitian. Generate precise daily nutrition targets for this patient.

Patient:
- Age: {profile.get('age')} | Sex: {profile.get('sex')} | BMI: {bmi}
- Blood pressure: {bp}
- Fasting blood sugar: {profile.get('fasting_blood_sugar', 'N/A')} mmol/L
- Cholesterol: {profile.get('total_cholesterol', 'N/A')} mmol/L
- Triglycerides: {profile.get('triglycerides', 'N/A')} mmol/L
- Diet: {', '.join(profile.get('dietary_preferences', ['no restriction']))}
- Avoid allergens: {', '.join(profile.get('allergens', ['none']))}
- Goals: {', '.join(goals) if goals else 'general health'}

Respond ONLY with valid JSON, no markdown:
{{
  "daily_calories": <integer>,
  "protein_g": <integer>,
  "carbs_g": <integer>,
  "fat_g": <integer>,
  "fiber_g": <integer>,
  "sodium_mg": <integer>,
  "ai_advice": "<2-3 sentences personalised advice>",
  "foods_to_eat": ["<food1>", "<food2>", "<food3>", "<food4>", "<food5>"],
  "foods_to_avoid": ["<food1>", "<food2>", "<food3>"]
}}"""

    print(f"🧠 Generating nutrition targets | BMI={bmi} | goals={goals}")
    response = model.generate_content(prompt)
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)
    print(f"✅ Nutrition targets: {result['daily_calories']} kcal/day")
    return result


# ════════════════════════════════════════════════════════════════
# 2. 生成健康报告（新增）
# ════════════════════════════════════════════════════════════════
def generate_health_report(profile: dict, goals: list, gemini_model,
                           meal_history: list = None) -> dict:
    from meal_analyzer import analyze_meal_history

    meal_analysis = analyze_meal_history(meal_history or [])
    meal_summary  = meal_analysis["summary_text"]
    has_meal_data = len(meal_analysis["frequent_foods"]) > 0

    height_m = profile.get("height_cm", 170) / 100
    weight   = profile.get("weight_kg", 70)
    bmi      = round(weight / (height_m ** 2), 1) if height_m > 0 else 0

    dietary_prefs = ", ".join(profile.get("dietary_preferences", [])) or "None"
    allergens     = ", ".join(profile.get("allergens", [])) or "None"

    # ── 新增：把结构化缺口数据直接格式化成字符串 ──────────────────────
    gaps          = meal_analysis["nutrient_gaps"]
    deficient     = gaps.get("deficient", [])
    excessive     = gaps.get("excessive", [])
    recent_avgs   = meal_analysis["nutrient_averages"].get("recent", {})
    top_foods     = [f["food"] for f in meal_analysis["frequent_foods"][:6]]
    cooking_prefs = meal_analysis["cooking_style_prefs"]

    # 格式化缺口：给 AI 提供精确数字
    def fmt_gaps(gap_list):
        if not gap_list:
            return "None detected"
        return "\n".join([
            f"  - {g['nutrient'].upper()}: avg {g['avg_daily']} "
            f"(reference {g['reference']}, only {int(g['ratio']*100)}% of target)"
            for g in gap_list
        ])

    # 格式化烹饪风格：给 AI 推荐 dish 时参考
    top_cooking = sorted(cooking_prefs.items(), key=lambda x: x[1], reverse=True)[:2]
    cooking_str = ", ".join([f"{s}({int(p*100)}%)" for s, p in top_cooking]) or "unknown"

    # 临床 flags：结构化判断，不依赖 AI 自己推断
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
        clinical_flags.append(
            f"OBESE (BMI {bmi}) → "
            f"recommend HIGH-SATIETY LOW-CALORIE-DENSITY foods"
        )
    elif bmi >= 25:
        clinical_flags.append(
            f"OVERWEIGHT (BMI {bmi}) → "
            f"recommend lean protein and fiber-rich foods for satiety"
        )
    elif bmi < 18.5:
        clinical_flags.append(
            f"UNDERWEIGHT (BMI {bmi}) → "
            f"recommend calorie-dense nutrient-rich foods"
        )

    clinical_str = "\n".join([f"  • {f}" for f in clinical_flags]) if clinical_flags else "  • All clinical markers within normal range"

    # ── 改进后的 Prompt ────────────────────────────────────────────────────
    prompt = f"""You are a clinical nutritionist. Generate a personalized health report.

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
{fmt_gaps(deficient)}

EXCESSES (above 130% of daily reference):
{fmt_gaps(excessive)}

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
→ e.g. "Your recent protein avg is only 32g/day vs. 50g reference (64%)..."

PRIORITY 3 — Fit user's existing taste/cooking style:
→ If user frequently eats stir-fries, suggest stir-fry-friendly ingredients.
→ If user frequently eats a specific protein, suggest a healthier variant.
→ Dish ideas must match cooking style: {cooking_str}

PRIORITY 4 — Fill remaining slots with balance foods.

REASON QUALITY RULES:
✅ GOOD: "Your fiber avg is only 8g/day (29% of 28g reference). Adding edamame to your frequent stir-fry meals adds 5g fiber per serving."
✅ GOOD: "Your sodium is running at 3100mg/day (135% of 2300mg limit). Replacing regular soy sauce with low-sodium versions cuts sodium by ~40%."
❌ BAD: "Rich in protein, which supports muscle health."
❌ BAD: "A great source of vitamins and minerals."

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
- recommended_foods: exactly 6 items, ordered by priority (clinical first, then gaps, then balance)
- attention_items: 2-5 items, omit metrics with N/A data
- dishes: must suit user's preferred cooking style ({cooking_str})
- foods_to_limit: based on what user actually eats frequently, not generic advice
- If meal data coverage < 30%, acknowledge limited data in health_summary
"""

    response = gemini_model.generate_content(prompt)
    raw = response.text.strip().replace("```json", "").replace("```", "").strip()

    start = raw.find("{")
    end   = raw.rfind("}") + 1
    if start >= 0 and end > start:
        raw = raw[start:end]

    result = json.loads(raw)

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

    result["weekly_calories"] = result.get(
        "weekly_calories", result["daily_calories"] * 7
    )
    result["meal_analysis_meta"] = {
        "has_meal_data":  has_meal_data,
        "data_coverage":  meal_analysis["data_coverage"],
        "top_foods":      top_foods,
        "nutrient_gaps":  meal_analysis["nutrient_gaps"],
    }

    return result

# ════════════════════════════════════════════════════════════════
# 3. 生成餐食计划（保留原有）
# ════════════════════════════════════════════════════════════════

def _build_day_prompt(day_date, day_name, day_index, cal, prot, carbs, fat,
                       diet, allergy, meals_per_day, meal_types):
    variety = VARIETY_HINTS[day_index % len(VARIETY_HINTS)]
    if meals_per_day == 1:
        cal_split = f"All {cal} kcal in one meal"
    elif meals_per_day == 2:
        b = int(cal * 0.45); l = cal - b
        cal_split = f"Meal 1: ~{b} kcal, Meal 2: ~{l} kcal"
    else:
        b = int(cal * 0.30); l = int(cal * 0.40); d = cal - b - l
        cal_split = f"Breakfast: ~{b} kcal, Lunch: ~{l} kcal, Dinner: ~{d} kcal"

    meal_jsons = []
    for mt in meal_types:
        meal_jsons.append(
            f'"{mt}":{{"meal_type":"{mt}","name":"<unique {mt} name>","items":[{{"food":"<specific food>","amount_g":<n>,"calories":<n>,"protein":<n>,"carbs":<n>,"fat":<n>}}],"total_calories":<n>,"total_protein":<n>,"total_carbs":<n>,"total_fat":<n>}}'
        )

    return (
        f"You are a dietitian. Create a UNIQUE ONE-DAY meal plan. Return JSON only, no markdown.\n"
        f"Day: {day_name} {day_date} (Day {day_index + 1})\n"
        f"TODAY'S CUISINE THEME: {variety}\n"
        f"Targets: {cal} kcal | P{prot}g C{carbs}g F{fat}g | {cal_split}\n"
        f"Diet: {diet} | Avoid: {allergy}\n"
        f"IMPORTANT: Use ONLY {day_name}'s cuisine theme. Every meal must be COMPLETELY DIFFERENT from other days.\n\n"
        f"Return ONLY this JSON:\n"
        f'{{"date":"{day_date}","day_name":"{day_name}",'
        + ",".join(meal_jsons) +
        f',"total_calories":<n>}}\n\n'
        f"Rules: 2-3 items per meal. Real specific food names. All integers. No nulls."
    )


def generate_meal_plan(nutrition_plan: dict, health_profile: dict, days: int = 7,
                        meals_per_day: int = 3, gemini_model=None) -> dict:
    flash = _flash_model or genai.GenerativeModel('gemini-2.5-flash')
    days = max(1, min(7, days))
    meals_per_day = max(1, min(3, meals_per_day))

    today = datetime.now()
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    days_info = []
    for i in range(days):
        d = today + timedelta(days=i)
        days_info.append({"date": d.strftime("%Y-%m-%d"), "day_name": day_names[d.weekday()], "index": i})

    if meals_per_day == 1:
        meal_types = ["lunch"]
    elif meals_per_day == 2:
        meal_types = ["breakfast", "dinner"]
    else:
        meal_types = ["breakfast", "lunch", "dinner"]

    cal     = nutrition_plan.get("daily_calories", 2000)
    prot    = nutrition_plan.get("protein_g", 100)
    carbs   = nutrition_plan.get("carbs_g", 250)
    fat     = nutrition_plan.get("fat_g", 65)
    diet    = ", ".join(health_profile.get("dietary_preferences", ["none"]))
    allergy = ", ".join(health_profile.get("allergens", ["none"]))

    def generate_single_day(day: dict) -> dict:
        prompt = _build_day_prompt(
            day["date"], day["day_name"], day["index"],
            cal, prot, carbs, fat, diet, allergy, meals_per_day, meal_types
        )
        response = flash.generate_content(prompt)
        text = re.sub(r"```json|```", "", response.text).strip()
        result = json.loads(text)
        for mt in ["breakfast", "lunch", "dinner"]:
            if mt not in result:
                result[mt] = None
        return result

    def fallback_day(day: dict) -> dict:
        cuisines = ["Oatmeal", "Chicken Salad", "Grilled Fish", "Vegetable Stir Fry",
                    "Quinoa Bowl", "Lentil Soup", "Avocado Toast"]
        name = cuisines[day["index"] % len(cuisines)]
        base = {
            "date": day["date"], "day_name": day["day_name"],
            "breakfast": {"meal_type": "breakfast", "name": f"{name} Breakfast",
                "items": [{"food": "Oatmeal", "amount_g": 80, "calories": 300, "protein": 10, "carbs": 55, "fat": 5}],
                "total_calories": 300, "total_protein": 10, "total_carbs": 55, "total_fat": 5},
            "lunch": {"meal_type": "lunch", "name": f"{name} Lunch",
                "items": [{"food": "Grilled chicken breast", "amount_g": 150, "calories": 250, "protein": 40, "carbs": 0, "fat": 6}],
                "total_calories": 485, "total_protein": 47, "total_carbs": 51, "total_fat": 8},
            "dinner": {"meal_type": "dinner", "name": f"{name} Dinner",
                "items": [{"food": "Salmon fillet", "amount_g": 150, "calories": 300, "protein": 35, "carbs": 0, "fat": 15}],
                "total_calories": 450, "total_protein": 38, "total_carbs": 34, "total_fat": 15},
            "total_calories": 1235
        }
        for mt in ["breakfast", "lunch", "dinner"]:
            if mt not in meal_types:
                base[mt] = None
        return base

    print(f"🍽️ Generating {days}-day meal plan | parallel")
    day_results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(days, 7)) as executor:
        futures = {executor.submit(generate_single_day, day): i for i, day in enumerate(days_info)}
        for future in concurrent.futures.as_completed(futures):
            i = futures[future]
            try:
                day_results[i] = future.result()
            except Exception as e:
                print(f"  ❌ Day {i} failed: {e}")
                day_results[i] = fallback_day(days_info[i])

    all_days = [day_results[i] for i in range(days)]
    return {
        "week_start_date": days_info[0]["date"],
        "days": all_days,
        "plan_config": {"days": days, "meals_per_day": meals_per_day, "meal_types": meal_types}
    }


def generate_weekly_meal_plan(nutrition_plan: dict, health_profile: dict, gemini_model=None,
                               days: int = 7, meals_per_day: int = 3) -> dict:
    return generate_meal_plan(nutrition_plan, health_profile, days, meals_per_day, gemini_model)


# ════════════════════════════════════════════════════════════════
# 4. 分析餐食照片（保留原有）
# ════════════════════════════════════════════════════════════════

def analyze_meal_photo(image_b64, meal_type, planned_meal, remaining_plan,
                       gemini_model=None, user_id=None, today_logs=None):
    import base64, tempfile, os
    from model_pipeline import full_image_analysis

    print(f"📸 Starting full image analysis | meal_type={meal_type}")
    try:
        img_data = base64.b64decode(image_b64)
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp.write(img_data)
            tmp_path = tmp.name

        analysis = full_image_analysis(tmp_path, user_id or "health_agent")
        try: os.remove(tmp_path)
        except: pass

        if "error" in analysis or not analysis.get("nutrition_info"):
            raise Exception(f"model_pipeline failed: {analysis.get('error', 'empty nutrition_info')}")

        dish_name      = analysis.get("dish_prediction", "Unknown dish")
        visible_ingr   = analysis.get("image_description", "")
        hidden_ingr    = analysis.get("hidden_ingredients", "")
        nutrition_info = analysis.get("nutrition_info", "")

        def parse_nutrient(text, key):
            for line in text.split("\n"):
                parts = [p.strip() for p in line.split("|")]
                if len(parts) >= 2 and key.lower() in parts[0].lower():
                    try: return int(float(parts[1].replace(",","")))
                    except: pass
            return 0

        actual_cal   = parse_nutrient(nutrition_info, "calorie")
        actual_prot  = parse_nutrient(nutrition_info, "protein")
        actual_carbs = parse_nutrient(nutrition_info, "carb")
        actual_fat   = parse_nutrient(nutrition_info, "fat")
        actual_sodium = parse_nutrient(nutrition_info, "sodium")
        actual_sugar  = parse_nutrient(nutrition_info, "sugar")

        detected_foods = []
        for line in visible_ingr.split("\n"):
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3 and parts[0]:
                detected_foods.append(f"{parts[0]} ~{parts[1]}{parts[2]}")

    except Exception as e:
        print(f"❌ Image analysis failed: {e}, falling back to AI estimate")
        model = _get_model(gemini_model)
        prompt = f"""Analyze this {meal_type} photo. Return ONLY JSON:
{{"detected_foods":["<food ~Xg>"],"estimated_calories":<int>,"estimated_protein":<int>,"estimated_carbs":<int>,"estimated_fat":<int>,"sodium_mg":<int>,"sugar_g":<int>,"dish_name":"<name>","nutrition_info":"Calories|<n>|kcal\nProtein|<n>|g\nFat|<n>|g\nCarbohydrates|<n>|g\nFiber|<n>|g\nSugar|<n>|g\nSodium|<n>|mg"}}"""
        response = model.generate_content([prompt, {"inline_data": {"mime_type": "image/jpeg", "data": image_b64}}])
        fb = json.loads(response.text.strip().replace("```json","").replace("```","").strip())
        dish_name = fb.get("dish_name", "Unknown")
        detected_foods = fb.get("detected_foods", [])
        actual_cal   = fb.get("estimated_calories", 0)
        actual_prot  = fb.get("estimated_protein", 0)
        actual_carbs = fb.get("estimated_carbs", 0)
        actual_fat   = fb.get("estimated_fat", 0)
        actual_sodium = fb.get("sodium_mg", 0)
        actual_sugar  = fb.get("sugar_g", 0)
        nutrition_info = fb.get("nutrition_info", f"Calories|{actual_cal}|kcal\nProtein|{actual_prot}|g\nFat|{actual_fat}|g\nCarbohydrates|{actual_carbs}|g\nFiber|0|g\nSugar|{actual_sugar}|g\nSodium|{actual_sodium}|mg")
        visible_ingr = "\n".join(detected_foods)
        hidden_ingr = ""

    # 对比计划
    planned_cal  = planned_meal.get("total_calories", 0) if planned_meal else 0
    planned_prot = planned_meal.get("total_protein", 0) if planned_meal else 0

    def within_range(actual, target, tolerance=0.25):
        if target == 0: return True
        return abs(actual - target) / target <= tolerance

    scores = []
    if planned_cal > 0:
        scores.append(100 if within_range(actual_cal, planned_cal) else
                      max(0, 100 - int(abs(actual_cal - planned_cal) / planned_cal * 100)))
    if planned_prot > 0:
        scores.append(100 if within_range(actual_prot, planned_prot) else
                      max(0, 100 - int(abs(actual_prot - planned_prot) / planned_prot * 100)))
    compliance_score = int(sum(scores) / len(scores)) if scores else 70

    tips = []
    if actual_sodium > 1500:
        tips.append(f"⚠️ High sodium ({actual_sodium}mg) — reduce salt in remaining meals.")
    if planned_prot > 0 and actual_prot < planned_prot * 0.6:
        tips.append(f"💪 Low protein — add more protein in your next meal.")
    if planned_cal > 0 and actual_cal > planned_cal * 1.3:
        tips.append(f"🔥 Over calorie target — consider lighter options later.")

    if planned_cal > 0:
        cal_diff = actual_cal - planned_cal
        if abs(cal_diff) <= planned_cal * 0.15:
            feedback = f"Great match! Your meal is within the planned calorie range ({actual_cal} vs {planned_cal} kcal)."
        elif cal_diff > 0:
            feedback = f"Meal is {cal_diff} kcal over plan."
        else:
            feedback = f"Meal is {abs(cal_diff)} kcal under plan."
    else:
        feedback = f"Meal analyzed: {actual_cal} kcal, {actual_prot}g protein."

    if tips:
        feedback += " " + tips[0]

    remaining_days = [d.get("day_name", "") for d in remaining_plan if d]
    adjustment_note = None
    if compliance_score < 60 and remaining_days:
        short = planned_prot > 0 and actual_prot < planned_prot * 0.7
        over  = planned_cal > 0 and actual_cal > planned_cal * 1.2
        if short:
            adjustment_note = f"Add extra protein in your {remaining_days[0]} meals."
        elif over:
            adjustment_note = f"Reduce portion sizes by ~20% for {remaining_days[0]}."

    return {
        "detected_foods": detected_foods,
        "estimated_calories": actual_cal,
        "estimated_protein": actual_prot,
        "estimated_carbs": actual_carbs,
        "estimated_fat": actual_fat,
        "compliance_score": compliance_score,
        "compliance_feedback": feedback,
        "plan_adjustment_note": adjustment_note,
        "dish_prediction": dish_name,
        "image_description": visible_ingr,
        "hidden_ingredients": hidden_ingr,
        "nutrition_info": nutrition_info,
        "meal_type": meal_type,
    }


def calculate_bmi(height_cm: float, weight_kg: float) -> dict:
    h = height_cm / 100
    bmi = round(weight_kg / (h * h), 1)
    if bmi < 18.5:   cat = "Underweight"
    elif bmi < 25:   cat = "Normal"
    elif bmi < 30:   cat = "Overweight"
    else:            cat = "Obese"
    return {"bmi": bmi, "category": cat}






def generate_health_report(profile: dict, goals: list, gemini_model,
                           meal_history: list = None) -> dict:
    """
    Generate a personalized health report.
 
    Integrates meal_analyzer's 3-tier weighted time window analysis so that
    food recommendations are grounded in the user's actual eating patterns,
    not just their clinical markers.
 
    Parameters:
        profile:      HealthProfile dict (height, weight, BP, glucose, etc.)
        goals:        List of health goal strings
        gemini_model: Gemini model instance
        meal_history: List of meal dicts from the last 90 days (optional).
                      Fetched in app.py before calling this function.
 
    Returns:
        dict matching the HealthReport Swift model, plus meal_analysis_meta.
    """
    import json
    from meal_analyzer import analyze_meal_history
 
    # Analyze meal history using 3-tier weighted windows
    meal_analysis    = analyze_meal_history(meal_history or [])
    meal_summary     = meal_analysis["summary_text"]
    has_meal_data    = len(meal_analysis["frequent_foods"]) > 0
 
    # Basic derived metrics
    height_m = profile.get("height_cm", 170) / 100
    weight   = profile.get("weight_kg", 70)
    bmi      = round(weight / (height_m ** 2), 1) if height_m > 0 else 0
 
    dietary_prefs = ", ".join(profile.get("dietary_preferences", [])) or "None"
    allergens     = ", ".join(profile.get("allergens", [])) or "None"
 
    # Nutrient gap shorthand for use inside the prompt
    recent_nutrients = meal_analysis["nutrient_averages"].get("recent", {})
    avg_protein      = recent_nutrients.get("protein", "unknown")
    avg_sodium       = recent_nutrients.get("sodium",  "unknown")
 
    prompt = f"""You are a professional nutritionist. Generate a personalized health report.
 
=== USER HEALTH PROFILE ===
Age: {profile.get("age", 25)}, Sex: {profile.get("sex", "unknown")}
Height: {profile.get("height_cm", 170)}cm, Weight: {weight}kg, BMI: {bmi}
Blood Pressure: {profile.get("systolic_bp", "N/A")}/{profile.get("diastolic_bp", "N/A")} mmHg
Fasting Blood Sugar: {profile.get("fasting_blood_sugar", "N/A")} mmol/L
Total Cholesterol: {profile.get("total_cholesterol", "N/A")} mmol/L
Triglycerides: {profile.get("triglycerides", "N/A")} mmol/L
Health Goals: {", ".join(goals) if goals else "General wellness"}
Dietary Preferences: {dietary_prefs}
Allergens to avoid: {allergens}
 
=== MEAL HISTORY ANALYSIS (3-tier weighted: 7d/30d/90d) ===
{meal_summary}
 
=== YOUR TASK ===
 
Follow these four steps explicitly in your reasoning:
 
STEP 1 — INTERPRET MEAL DATA:
- What does this user actually eat regularly?
- What cooking styles do they prefer?
- Which nutrients are consistently low (deficient) or high (excessive)?
- Is their recent diet better or worse than their long-term baseline?
 
STEP 2 — IDENTIFY HEALTH PRIORITIES:
- Which clinical markers need attention?
- What dietary changes would have the highest impact?
- What must be excluded due to allergens or dietary preferences?
 
STEP 3 — GENERATE FOOD RECOMMENDATIONS (most important step):
Rules for the 6 recommendations:
- At least 3 must directly address identified nutrient deficiencies or excesses.
- Foods should fit the user's existing taste profile where possible.
  Example: if they eat a lot of chicken, suggest a healthier chicken preparation
  rather than asking them to switch to a completely unfamiliar protein.
- If a food category is completely absent from their history, suggest an
  approachable entry point for that category.
- Each "reason" field MUST be specific — never generic.
  BAD:  "Rich in protein, which is important for health."
  GOOD: "Your recent meals average only {avg_protein}g protein/day (reference: 50g).
         Adding edamame to your stir-fry dishes — which you already cook regularly —
         would boost protein without changing your preferred cooking style."
  GOOD: "Your sodium intake is running high ({avg_sodium}mg/day vs. 2300mg reference).
         Replacing regular soy sauce with low-sodium versions in your frequent
         stir-fry meals could reduce sodium by ~30% with minimal taste change."
 
STEP 4 — FOODS TO LIMIT:
Base this on what the user actually eats frequently, not generic advice.
 
Respond ONLY with valid JSON — no markdown, no explanation:
{{
  "health_score": <integer 0-100>,
  "health_summary": "<2-3 sentences referencing the user's ACTUAL eating patterns>",
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
      "metric": "<metric name>",
      "current_value": "<value with unit>",
      "status": "<normal|borderline|high|low>",
      "advice": "<specific, actionable advice>"
    }}
  ],
  "recommended_foods": [
    {{
      "food": "<food name>",
      "reason": "<specific reason referencing meal data or clinical marker — see STEP 3>",
      "analysis_basis": "<meal_history_pattern|clinical_marker|dietary_preference|general_health>",
      "dishes": ["<dish idea 1>", "<dish idea 2>", "<dish idea 3>"]
    }}
  ],
  "foods_to_limit": ["<food 1>", "<food 2>", "<food 3>"],
  "lifestyle_tip": "<specific tip based on the user's actual patterns>"
}}
 
Constraints:
- recommended_foods: exactly 6 items
- attention_items: 2-5 items (omit metrics with N/A data)
- All recommendations must respect allergens and dietary preferences
- If meal data coverage is below 30%, acknowledge the limited data in health_summary
"""
 
    response = gemini_model.generate_content(prompt)
    raw = response.text.strip().replace("```json", "").replace("```", "").strip()
 
    # Extract JSON safely (defensive against Gemini adding surrounding text)
    start = raw.find("{")
    end   = raw.rfind("}") + 1
    if start >= 0 and end > start:
        raw = raw[start:end]
 
    result = json.loads(raw)
 
    # Fill in defaults for any missing fields
    defaults = {
        "health_score":    70,
        "health_summary":  "Health analysis complete.",
        "status_badge":    "Good",
        "daily_calories":  2000,
        "protein_g":       100,
        "carbs_g":         250,
        "fat_g":           65,
        "fiber_g":         25,
        "sodium_mg":       2300,
        "attention_items":    [],
        "recommended_foods":  [],
        "foods_to_limit":     [],
        "lifestyle_tip":   "Stay consistent with your healthy habits.",
    }
    for key, value in defaults.items():
        result.setdefault(key, value)
 
    result["weekly_calories"] = result.get(
        "weekly_calories", result["daily_calories"] * 7
    )
 
    # Attach analysis metadata for transparency (optionally displayed in iOS)
    result["meal_analysis_meta"] = {
        "has_meal_data": has_meal_data,
        "data_coverage": meal_analysis["data_coverage"],
        "top_foods":     [f["food"] for f in meal_analysis["frequent_foods"][:5]],
        "nutrient_gaps": meal_analysis["nutrient_gaps"],
    }
 
    return result
 
 
