# health_pipeline.py
# Health Agent — AI 逻辑层
# app.py 通过 import 调用这里的函数
# 跟 model_pipeline.py 的架构完全一致
# health_pipeline.py
# Health Agent — AI 逻辑层
# app.py 通过 import 调用这里的函数

import google.generativeai as genai
import os
import re
import json
import traceback
import concurrent.futures
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

# ── Gemini 初始化
GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
    _model      = genai.GenerativeModel('gemini-2.5-pro')
    _flash_model = genai.GenerativeModel('gemini-2.5-flash')  # 用于餐食计划生成（快速）
else:
    _model = _flash_model = None
    print("⚠️ health_pipeline: GEMINI_API_KEY not set")

 
# 保证每天饮食不同的多样化食材库
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
# 2. 生成餐食计划（支持自定义天数和餐次）
# ════════════════════════════════════════════════════════════════
 
def _build_day_prompt(day_date, day_name, day_index, cal, prot, carbs, fat,
                       diet, allergy, meals_per_day, meal_types):
    """每天用不同的菜系提示，保证多样性"""
    variety = VARIETY_HINTS[day_index % len(VARIETY_HINTS)]
 
    # 按餐次分配卡路里
    if meals_per_day == 1:
        cal_split = f"All {cal} kcal in one meal"
    elif meals_per_day == 2:
        b = int(cal * 0.45); l = cal - b
        cal_split = f"Meal 1: ~{b} kcal, Meal 2: ~{l} kcal"
    else:
        b = int(cal * 0.30); l = int(cal * 0.40); d = cal - b - l
        cal_split = f"Breakfast: ~{b} kcal, Lunch: ~{l} kcal, Dinner: ~{d} kcal"
 
    # 构建 JSON 模板
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
        f"Return ONLY this JSON (replace all placeholders with real unique food names and real numbers):\n"
        f'{{"date":"{day_date}","day_name":"{day_name}",'
        + ",".join(meal_jsons) +
        f',"total_calories":<n>}}\n\n'
        f"Rules: 2-3 items per meal. Real specific food names. All integers. No nulls. No placeholders."
    )
 
 
def generate_meal_plan(
    nutrition_plan: dict,
    health_profile: dict,
    days: int = 7,
    meals_per_day: int = 3,
    gemini_model=None
) -> dict:
    """
    生成餐食计划。
    - days: 1-7天，从今天开始
    - meals_per_day: 1-3餐
    - 每天完全不同的菜系
    - 并行生成
    """
    flash = _flash_model or genai.GenerativeModel('gemini-2.5-flash')
    days = max(1, min(7, days))
    meals_per_day = max(1, min(3, meals_per_day))
 
    # 从今天开始
    today = datetime.now()
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    days_info = []
    for i in range(days):
        d = today + timedelta(days=i)
        days_info.append({
            "date": d.strftime("%Y-%m-%d"),
            "day_name": day_names[d.weekday()],
            "index": i
        })
 
    # 确定每天的餐次
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
            cal, prot, carbs, fat, diet, allergy,
            meals_per_day, meal_types
        )
        print(f"  📅 {day['day_name']} {day['date']} (theme: {VARIETY_HINTS[day['index'] % len(VARIETY_HINTS)][:20]}...)")
        response = flash.generate_content(prompt)
        text = re.sub(r"```json|```", "", response.text).strip()
        result = json.loads(text)
        # 确保所有餐次存在（补全缺失的）
        for mt in ["breakfast", "lunch", "dinner"]:
            if mt not in result:
                result[mt] = None
        print(f"  ✅ {day['day_name']} done")
        return result
 
    def fallback_day(day: dict) -> dict:
        """生成失败时的兜底数据"""
        cuisines = ["Oatmeal", "Chicken Salad", "Grilled Fish", "Vegetable Stir Fry",
                    "Quinoa Bowl", "Lentil Soup", "Avocado Toast"]
        name = cuisines[day["index"] % len(cuisines)]
        base = {
            "date": day["date"], "day_name": day["day_name"],
            "breakfast": {"meal_type": "breakfast", "name": f"{name} Breakfast",
                "items": [{"food": "Oatmeal", "amount_g": 80, "calories": 300, "protein": 10, "carbs": 55, "fat": 5},
                           {"food": "Banana", "amount_g": 100, "calories": 90, "protein": 1, "carbs": 23, "fat": 0}],
                "total_calories": 390, "total_protein": 11, "total_carbs": 78, "total_fat": 5},
            "lunch": {"meal_type": "lunch", "name": f"{name} Lunch",
                "items": [{"food": "Grilled chicken breast", "amount_g": 150, "calories": 250, "protein": 40, "carbs": 0, "fat": 6},
                           {"food": "Brown rice", "amount_g": 120, "calories": 200, "protein": 4, "carbs": 44, "fat": 2},
                           {"food": "Steamed broccoli", "amount_g": 100, "calories": 35, "protein": 3, "carbs": 7, "fat": 0}],
                "total_calories": 485, "total_protein": 47, "total_carbs": 51, "total_fat": 8},
            "dinner": {"meal_type": "dinner", "name": f"{name} Dinner",
                "items": [{"food": "Salmon fillet", "amount_g": 150, "calories": 300, "protein": 35, "carbs": 0, "fat": 15},
                           {"food": "Sweet potato", "amount_g": 150, "calories": 130, "protein": 2, "carbs": 30, "fat": 0},
                           {"food": "Mixed greens salad", "amount_g": 80, "calories": 20, "protein": 1, "carbs": 4, "fat": 0}],
                "total_calories": 450, "total_protein": 38, "total_carbs": 34, "total_fat": 15},
            "total_calories": 1325
        }
        # 如果不是3餐，清空不需要的
        for mt in ["breakfast", "lunch", "dinner"]:
            if mt not in meal_types:
                base[mt] = None
        return base
 
    print(f"🍽️ gemini-2.5-flash | {cal} kcal | {days} days from today | {meals_per_day} meals/day | parallel")
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
    print(f"✅ Meal plan ready | {len(all_days)} days")
    return {
        "week_start_date": days_info[0]["date"],
        "days": all_days,
        "plan_config": {"days": days, "meals_per_day": meals_per_day, "meal_types": meal_types}
    }
 
 
# 保持向后兼容（旧代码调用 generate_weekly_meal_plan）
def generate_weekly_meal_plan(nutrition_plan: dict, health_profile: dict, gemini_model=None,
                               days: int = 7, meals_per_day: int = 3) -> dict:
    return generate_meal_plan(nutrition_plan, health_profile, days, meals_per_day, gemini_model)
 
 
# ════════════════════════════════════════════════════════════════
# 3. 分析餐食照片
# ════════════════════════════════════════════════════════════════
 
def analyze_meal_photo(image_b64, meal_type, planned_meal, remaining_plan, gemini_model=None):
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")
 
    planned_summary = "No specific meal planned."
    if planned_meal:
        items = planned_meal.get("items", [])
        item_names = ", ".join(item.get("food", "") for item in items)
        planned_summary = (
            f"Planned {meal_type}: {planned_meal.get('name','N/A')}\n"
            f"- Target: {planned_meal.get('total_calories','N/A')} kcal | "
            f"P{planned_meal.get('total_protein','N/A')}g C{planned_meal.get('total_carbs','N/A')}g F{planned_meal.get('total_fat','N/A')}g\n"
            f"- Foods: {item_names}"
        )
 
    remaining_days = [d.get("day_name", "") for d in remaining_plan if d]
    remaining_str  = ", ".join(remaining_days) if remaining_days else "none"
 
    prompt_text = f"""Clinical dietitian analyzing meal photo for compliance.
 
{planned_summary}
Remaining days: {remaining_str}
 
Analyze this image:
1. Identify all foods with gram estimates
2. Calculate nutrition totals
3. Score compliance 0-100 vs plan
4. Suggest adjustments for remaining days if needed
 
Return ONLY valid JSON, no markdown:
{{
  "detected_foods": ["<food ~Xg>"],
  "estimated_calories": <int>,
  "estimated_protein": <int>,
  "estimated_carbs": <int>,
  "estimated_fat": <int>,
  "compliance_score": <0-100>,
  "compliance_feedback": "<1-2 sentences>",
  "plan_adjustment_note": "<advice or null>"
}}"""
 
    print(f"📸 Analyzing meal | type={meal_type}")
    response = model.generate_content([prompt_text, {"inline_data": {"mime_type": "image/jpeg", "data": image_b64}}])
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)
    print(f"✅ Photo analyzed | score={result.get('compliance_score')}%")
    return result
 
 
def calculate_bmi(height_cm: float, weight_kg: float) -> dict:
    h = height_cm / 100
    bmi = round(weight_kg / (h * h), 1)
    if bmi < 18.5:   cat = "Underweight"
    elif bmi < 25:   cat = "Normal"
    elif bmi < 30:   cat = "Overweight"
    else:            cat = "Obese"
    return {"bmi": bmi, "category": cat}
 
