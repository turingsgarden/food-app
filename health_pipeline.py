# health_pipeline.py
# Health Agent — AI 逻辑层
# app.py 通过 import 调用这里的函数
# 跟 model_pipeline.py 的架构完全一致

import google.generativeai as genai
import os
import json
import traceback
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

# ── Gemini 初始化（复用 app.py 已有的，这里做备用）──────────────
GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
    _model = genai.GenerativeModel('gemini-2.5-pro')
else:
    _model = None
    print("⚠️ health_pipeline: GEMINI_API_KEY not set")


def _get_model(gemini_model=None):
    """优先用 app.py 传入的 model，其次用本文件自己初始化的"""
    return gemini_model or _model


# ════════════════════════════════════════════════════════════════
# 1. 生成营养目标
# ════════════════════════════════════════════════════════════════

def generate_nutrition_targets(profile: dict, goals: list, gemini_model=None) -> dict:
    """
    根据健康档案和目标，用 Gemini 生成每日营养目标。
    返回 dict，包含 daily_calories / protein_g / ... / ai_advice 等。
    """
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    # 计算 BMI
    height_m = profile.get("height_cm", 170) / 100
    weight   = profile.get("weight_kg", 70)
    bmi      = round(weight / (height_m ** 2), 1)

    # 血压显示
    bp = "N/A"
    if profile.get("systolic_bp") and profile.get("diastolic_bp"):
        bp = f"{profile['systolic_bp']}/{profile['diastolic_bp']} mmHg"

    prompt = f"""You are a clinical dietitian. Generate precise daily nutrition targets for this patient.

Patient profile:
- Age: {profile.get('age', 'unknown')}
- Sex: {profile.get('sex', 'unknown')}
- Height: {profile.get('height_cm', 'N/A')} cm
- Weight: {profile.get('weight_kg', 'N/A')} kg
- BMI: {bmi}
- Blood pressure: {bp}
- Fasting blood sugar: {profile.get('fasting_blood_sugar', 'N/A')} mmol/L
- Total cholesterol: {profile.get('total_cholesterol', 'N/A')} mmol/L
- Triglycerides: {profile.get('triglycerides', 'N/A')} mmol/L
- Dietary preferences: {', '.join(profile.get('dietary_preferences', ['no restriction']))}
- Allergens to avoid: {', '.join(profile.get('allergens', ['none']))}
- Health goals: {', '.join(goals) if goals else 'general health maintenance'}

Respond ONLY with valid JSON, no markdown, no extra text:
{{
  "daily_calories": <integer>,
  "protein_g": <integer>,
  "carbs_g": <integer>,
  "fat_g": <integer>,
  "fiber_g": <integer>,
  "sodium_mg": <integer>,
  "ai_advice": "<2-3 sentences of personalised clinical advice based on the specific health markers above>",
  "foods_to_eat": ["<food1>", "<food2>", "<food3>", "<food4>", "<food5>"],
  "foods_to_avoid": ["<food1>", "<food2>", "<food3>"]
}}"""

    print(f"🧠 Generating nutrition targets | BMI={bmi} | goals={goals}")
    response = model.generate_content(prompt)
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)

    print(f"✅ Nutrition targets generated: {result['daily_calories']} kcal/day")
    return result


# ════════════════════════════════════════════════════════════════
# 2. 生成一周餐食计划
# ════════════════════════════════════════════════════════════════

def _build_day_prompt(day_date, day_name, cal, prot, carbs, fat, diet, allergy):
    """극简 single-day prompt — 固定 JSON 结构，参考 model_pipeline 风格"""
    return (
        f"Dietitian: create ONE day meal plan. Return JSON only, no markdown.\n"
        f"Day: {day_name} {day_date}\n"
        f"Targets: {cal}kcal P{prot}g C{carbs}g F{fat}g\n"
        f"Diet: {diet} | Avoid: {allergy}\n"
        f"Format:\n"
        f'{{"date":"{day_date}","day_name":"{day_name}"'
        f',"breakfast":{{"meal_type":"breakfast","name":"<n>","items":[{{"food":"<f>","amount_g":100,"calories":200,"protein":10,"carbs":25,"fat":5}}],"total_calories":400,"total_protein":20,"total_carbs":50,"total_fat":10}}'
        f',"lunch":{{"meal_type":"lunch","name":"<n>","items":[...],"total_calories":500,"total_protein":30,"total_carbs":60,"total_fat":15}}'
        f',"dinner":{{"meal_type":"dinner","name":"<n>","items":[...],"total_calories":500,"total_protein":30,"total_carbs":60,"total_fat":15}}'
        f',"total_calories":1400}}\n'
        f"Rules: 2-3 real food items per meal. Replace ALL placeholder values with real numbers."
    )


def generate_weekly_meal_plan(nutrition_plan: dict, health_profile: dict, gemini_model=None) -> dict:
    """
    7天餐食计划 — gemini-2.5-pro，3批并行，每批极简 prompt。
    Batch 1: Mon-Wed | Batch 2: Thu-Fri | Batch 3: Sat-Sun
    """
    import re
    import concurrent.futures

    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    today      = datetime.now()
    week_start = today - timedelta(days=today.weekday())
    day_names  = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
    days_info  = []
    for i in range(7):
        d = week_start + timedelta(days=i)
        days_info.append({"date": d.strftime("%Y-%m-%d"), "day_name": day_names[i]})

    cal     = nutrition_plan.get("daily_calories", 2000)
    prot    = nutrition_plan.get("protein_g", 100)
    carbs   = nutrition_plan.get("carbs_g", 250)
    fat     = nutrition_plan.get("fat_g", 65)
    diet    = ", ".join(health_profile.get("dietary_preferences", ["none"]))
    allergy = ", ".join(health_profile.get("allergens", ["none"]))

    def generate_single_day(day: dict) -> dict:
        prompt = _build_day_prompt(
            day["date"], day["day_name"],
            cal, prot, carbs, fat, diet, allergy
        )
        print(f"  📅 {day['day_name']} {day['date']}...")
        response = model.generate_content(prompt)
        text = re.sub(r"```json|```", "", response.text).strip()
        return json.loads(text)

    def generate_batch(batch_days: list) -> list:
        results = []
        for day in batch_days:
            results.append(generate_single_day(day))
        return results

    batches = [days_info[0:3], days_info[3:5], days_info[5:7]]
    print(f"🍽️ gemini-2.5-pro | {cal} kcal/day | 3 parallel batches")

    batch_results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(generate_batch, b): i for i, b in enumerate(batches)}
        for future in concurrent.futures.as_completed(futures):
            i = futures[future]
            batch_results[i] = future.result()
            print(f"✅ Batch {i+1}/3 complete")

    all_days = []
    for i in range(3):
        all_days.extend(batch_results[i])

    print(f"✅ Meal plan ready | {len(all_days)} days")
    return {"week_start_date": days_info[0]["date"], "days": all_days}


# ════════════════════════════════════════════════════════════════
# 3. 分析餐食照片（合规检查）
# ════════════════════════════════════════════════════════════════

def analyze_meal_photo(
    image_b64: str,
    meal_type: str,
    planned_meal: dict,
    remaining_plan: list,
    gemini_model=None
) -> dict:
    """
    用 Gemini Vision 分析照片，检查是否符合计划，
    并给出对本周剩余计划的调整建议。
    返回 MealLog 数据结构的 dict。
    """
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    # 整理计划摘要
    planned_summary = "No specific meal was planned."
    if planned_meal:
        items = planned_meal.get("items", [])
        item_names = ", ".join(item.get("food", "") for item in items)
        planned_summary = f"""Planned {meal_type}:
- Meal name: {planned_meal.get('name', 'N/A')}
- Target calories: {planned_meal.get('total_calories', 'N/A')} kcal
- Target protein: {planned_meal.get('total_protein', 'N/A')}g
- Target carbs: {planned_meal.get('total_carbs', 'N/A')}g
- Target fat: {planned_meal.get('total_fat', 'N/A')}g
- Planned foods: {item_names}"""

    remaining_days = [d.get("day_name", "") for d in remaining_plan if d]
    remaining_str  = ", ".join(remaining_days) if remaining_days else "none (last meal of the week)"

    prompt_text = f"""You are a clinical dietitian analyzing a meal photo for diet compliance.

{planned_summary}

Remaining days to potentially adjust: {remaining_str}

Analyze the food visible in this image and:
1. Identify ALL foods with realistic estimated gram weights
2. Calculate total nutritional content
3. Compare to the planned meal and give a compliance score (0-100)
   - 90-100: Almost perfect match
   - 70-89: Good, minor deviations
   - 50-69: Acceptable but notable differences
   - Below 50: Significant deviation from plan
4. If significantly off-plan, suggest specific adjustments for remaining days

Respond ONLY with valid JSON, no markdown:
{{
  "detected_foods": ["<food name ~Xg>", "<food name ~Xg>"],
  "estimated_calories": <integer>,
  "estimated_protein": <integer>,
  "estimated_carbs": <integer>,
  "estimated_fat": <integer>,
  "compliance_score": <0-100>,
  "compliance_feedback": "<1-2 honest sentences comparing actual vs planned>",
  "plan_adjustment_note": "<specific advice for remaining days to compensate, or null if on track>"
}}"""

    image_part = {
        "inline_data": {
            "mime_type": "image/jpeg",
            "data": image_b64
        }
    }

    print(f"📸 Analyzing meal photo | type={meal_type} | remaining_days={remaining_days}")
    response = model.generate_content([prompt_text, image_part])
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)

    print(f"✅ Photo analyzed | compliance={result.get('compliance_score')}%")
    return result


# ════════════════════════════════════════════════════════════════
# 工具函数
# ════════════════════════════════════════════════════════════════

def calculate_bmi(height_cm: float, weight_kg: float) -> dict:
    """计算 BMI 和分类"""
    h = height_cm / 100
    bmi = round(weight_kg / (h * h), 1)
    if bmi < 18.5:
        category = "Underweight"
    elif bmi < 25:
        category = "Normal"
    elif bmi < 30:
        category = "Overweight"
    else:
        category = "Obese"
    return {"bmi": bmi, "category": category}
