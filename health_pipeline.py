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
    _flash_model = genai.GenerativeModel('gemini-1.5-flash')  # 用于餐食计划生成（快速）
else:
    _model = _flash_model = None
    print("⚠️ health_pipeline: GEMINI_API_KEY not set")


def _get_model(gemini_model=None):
    return gemini_model or _model


# ════════════════════════════════════════════════════════════════
# 1. 生成营养目标（用 pro，只调用一次，不超时）
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
  "ai_advice": "<2-3 sentences of personalised clinical advice>",
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
# 2. 生成一周餐食计划
#    策略：用 gemini-1.5-flash（成熟稳定快速）
#    7天完全并行，每天独立请求，单请求约3-8秒
#    总时间 < 30秒，远低于 Render 60秒限制
# ════════════════════════════════════════════════════════════════

def _build_day_prompt(day_date, day_name, cal, prot, carbs, fat, diet, allergy):
    """极简 single-day prompt，固定 JSON 结构"""
    return (
        f"You are a dietitian. Create a ONE-DAY meal plan. Return JSON only, no markdown.\n"
        f"Day: {day_name} ({day_date})\n"
        f"Daily targets: {cal} kcal | protein {prot}g | carbs {carbs}g | fat {fat}g\n"
        f"Diet style: {diet} | Allergens to avoid: {allergy}\n\n"
        f"Return this exact JSON structure with real food and real numbers:\n"
        f'{{"date":"{day_date}","day_name":"{day_name}",'
        f'"breakfast":{{"meal_type":"breakfast","name":"<meal name>","items":[{{"food":"<food>","amount_g":<n>,"calories":<n>,"protein":<n>,"carbs":<n>,"fat":<n>}}],"total_calories":<n>,"total_protein":<n>,"total_carbs":<n>,"total_fat":<n>}},'
        f'"lunch":{{"meal_type":"lunch","name":"<meal name>","items":[...],"total_calories":<n>,"total_protein":<n>,"total_carbs":<n>,"total_fat":<n>}},'
        f'"dinner":{{"meal_type":"dinner","name":"<meal name>","items":[...],"total_calories":<n>,"total_protein":<n>,"total_carbs":<n>,"total_fat":<n>}},'
        f'"total_calories":<n>}}\n\n'
        f"Rules: 2-3 food items per meal. Use real foods. All numbers must be integers. No nulls."
    )


def generate_weekly_meal_plan(nutrition_plan: dict, health_profile: dict, gemini_model=None) -> dict:
    """
    7天餐食计划：
    - 使用 gemini-1.5-flash（成熟、快速、稳定）
    - 7天完全并行（ThreadPoolExecutor max_workers=7）
    - 每个请求独立，单天约3-8秒
    - 总时间预计 10-20秒，不会超时
    """
    # ✅ 始终用 flash 生成餐食计划，不用 pro
    flash = _flash_model or genai.GenerativeModel('gemini-1.5-flash')

    today      = datetime.now()
    week_start = today - timedelta(days=today.weekday())
    day_names  = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
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
        print(f"  📅 Generating {day['day_name']} {day['date']}...")
        response = flash.generate_content(prompt)
        text = re.sub(r"```json|```", "", response.text).strip()
        result = json.loads(text)
        print(f"  ✅ {day['day_name']} done")
        return result

    print(f"🍽️ gemini-1.5-flash | {cal} kcal/day | 7 days fully parallel")
    day_results = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=7) as executor:
        futures = {executor.submit(generate_single_day, day): i for i, day in enumerate(days_info)}
        for future in concurrent.futures.as_completed(futures):
            i = futures[future]
            try:
                day_results[i] = future.result()
            except Exception as e:
                print(f"  ❌ Day {i} failed: {e}, retrying with simpler prompt...")
                # 单天失败时用最简 fallback
                day = days_info[i]
                fallback_prompt = (
                    f"Create a simple meal plan for {day['day_name']}. "
                    f"Target: {cal} kcal. Diet: {diet}. Avoid: {allergy}. "
                    f"Return JSON: {{\"date\":\"{day['date']}\",\"day_name\":\"{day['day_name']}\","
                    f"\"breakfast\":{{\"meal_type\":\"breakfast\",\"name\":\"Oatmeal\",\"items\":[{{\"food\":\"Oatmeal\",\"amount_g\":80,\"calories\":300,\"protein\":10,\"carbs\":55,\"fat\":5}}],\"total_calories\":300,\"total_protein\":10,\"total_carbs\":55,\"total_fat\":5}},"
                    f"\"lunch\":{{\"meal_type\":\"lunch\",\"name\":\"Chicken Rice\",\"items\":[{{\"food\":\"Chicken breast\",\"amount_g\":150,\"calories\":250,\"protein\":40,\"carbs\":0,\"fat\":5}},{{\"food\":\"Brown rice\",\"amount_g\":100,\"calories\":200,\"protein\":4,\"carbs\":44,\"fat\":2}}],\"total_calories\":450,\"total_protein\":44,\"total_carbs\":44,\"total_fat\":7}},"
                    f"\"dinner\":{{\"meal_type\":\"dinner\",\"name\":\"Salmon Salad\",\"items\":[{{\"food\":\"Salmon\",\"amount_g\":150,\"calories\":300,\"protein\":35,\"carbs\":0,\"fat\":15}},{{\"food\":\"Mixed salad\",\"amount_g\":100,\"calories\":50,\"protein\":2,\"carbs\":10,\"fat\":1}}],\"total_calories\":350,\"total_protein\":37,\"total_carbs\":10,\"total_fat\":16}},"
                    f"\"total_calories\":1100}}"
                )
                try:
                    response = flash.generate_content(fallback_prompt)
                    text = re.sub(r"```json|```", "", response.text).strip()
                    day_results[i] = json.loads(text)
                except Exception as e2:
                    print(f"  ❌ Fallback also failed for day {i}: {e2}")
                    # 最后兜底：返回默认数据
                    day_results[i] = {
                        "date": day["date"], "day_name": day["day_name"],
                        "breakfast": {"meal_type": "breakfast", "name": "Oatmeal with Fruit",
                            "items": [{"food": "Oatmeal", "amount_g": 80, "calories": 300, "protein": 10, "carbs": 55, "fat": 5}],
                            "total_calories": 300, "total_protein": 10, "total_carbs": 55, "total_fat": 5},
                        "lunch": {"meal_type": "lunch", "name": "Grilled Chicken Rice",
                            "items": [{"food": "Chicken breast", "amount_g": 150, "calories": 250, "protein": 40, "carbs": 0, "fat": 5},
                                      {"food": "Brown rice", "amount_g": 100, "calories": 200, "protein": 4, "carbs": 44, "fat": 2}],
                            "total_calories": 450, "total_protein": 44, "total_carbs": 44, "total_fat": 7},
                        "dinner": {"meal_type": "dinner", "name": "Salmon with Vegetables",
                            "items": [{"food": "Salmon fillet", "amount_g": 150, "calories": 300, "protein": 35, "carbs": 0, "fat": 15},
                                      {"food": "Steamed broccoli", "amount_g": 150, "calories": 50, "protein": 4, "carbs": 10, "fat": 1}],
                            "total_calories": 350, "total_protein": 39, "total_carbs": 10, "total_fat": 16},
                        "total_calories": 1100
                    }

    all_days = [day_results[i] for i in range(7)]
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
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    planned_summary = "No specific meal was planned."
    if planned_meal:
        items = planned_meal.get("items", [])
        item_names = ", ".join(item.get("food", "") for item in items)
        planned_summary = (
            f"Planned {meal_type}:\n"
            f"- Name: {planned_meal.get('name', 'N/A')}\n"
            f"- Target calories: {planned_meal.get('total_calories', 'N/A')} kcal\n"
            f"- Target protein: {planned_meal.get('total_protein', 'N/A')}g\n"
            f"- Target carbs: {planned_meal.get('total_carbs', 'N/A')}g\n"
            f"- Target fat: {planned_meal.get('total_fat', 'N/A')}g\n"
            f"- Planned foods: {item_names}"
        )

    remaining_days = [d.get("day_name", "") for d in remaining_plan if d]
    remaining_str  = ", ".join(remaining_days) if remaining_days else "none (last meal of week)"

    prompt_text = f"""You are a clinical dietitian analyzing a meal photo for diet compliance.

{planned_summary}

Remaining days to potentially adjust: {remaining_str}

Analyze the food in this image:
1. Identify all foods with estimated gram weights
2. Calculate total nutrition
3. Score compliance 0-100 vs planned meal
4. Suggest adjustments for remaining days if needed

Respond ONLY with valid JSON, no markdown:
{{
  "detected_foods": ["<food ~Xg>", ...],
  "estimated_calories": <integer>,
  "estimated_protein": <integer>,
  "estimated_carbs": <integer>,
  "estimated_fat": <integer>,
  "compliance_score": <0-100>,
  "compliance_feedback": "<1-2 honest sentences>",
  "plan_adjustment_note": "<advice for remaining days or null>"
}}"""

    image_part = {"inline_data": {"mime_type": "image/jpeg", "data": image_b64}}

    print(f"📸 Analyzing meal photo | type={meal_type}")
    response = model.generate_content([prompt_text, image_part])
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)
    print(f"✅ Photo analyzed | compliance={result.get('compliance_score')}%")
    return result


# ════════════════════════════════════════════════════════════════
# 工具函数
# ════════════════════════════════════════════════════════════════

def calculate_bmi(height_cm: float, weight_kg: float) -> dict:
    h = height_cm / 100
    bmi = round(weight_kg / (h * h), 1)
    if bmi < 18.5:   category = "Underweight"
    elif bmi < 25:   category = "Normal"
    elif bmi < 30:   category = "Overweight"
    else:            category = "Obese"
    return {"bmi": bmi, "category": category}
