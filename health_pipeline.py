# health_pipeline.py
# Health Agent — AI 逻辑层

import google.generativeai as genai
import os
import re
import json
import traceback
import concurrent.futures
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
    _model       = genai.GenerativeModel('gemini-2.5-pro')
    _flash_model = genai.GenerativeModel('gemini-2.5-flash')
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
# 3. 分析餐食照片 — 用 model_pipeline 做真实营养分析，再对比计划
# ════════════════════════════════════════════════════════════════

def analyze_meal_photo(image_b64, meal_type, planned_meal, remaining_plan,
                       gemini_model=None, user_id=None, today_logs=None):
    """
    Step 1: 用 model_pipeline.full_image_analysis 真实分析图片食物和营养
    Step 2: 对比计划营养目标（±20% 为 acceptable range）
    Step 3: 给个性化建议（钠太高、蛋白质不足、重复菜式等）
    Step 4: 返回完整结果，包含可保存到 meal history 的数据
    """
    import base64, tempfile, os
    from model_pipeline import full_image_analysis

    # ── Step 1: 真实图片分析 ──
    print(f"📸 Starting full image analysis | meal_type={meal_type}")
    try:
        # 把 base64 写成临时文件给 model_pipeline
        img_data = base64.b64decode(image_b64)
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp.write(img_data)
            tmp_path = tmp.name

        analysis = full_image_analysis(tmp_path, user_id or "health_agent")
        try: os.remove(tmp_path)
        except: pass

        # ✅ 检查 model_pipeline 是否成功
        if "error" in analysis or not analysis.get("nutrition_info"):
            raise Exception(f"model_pipeline failed: {analysis.get('error', 'empty nutrition_info')}")

        dish_name      = analysis.get("dish_prediction", "Unknown dish")
        visible_ingr   = analysis.get("image_description", "")
        hidden_ingr    = analysis.get("hidden_ingredients", "")
        nutrition_info = analysis.get("nutrition_info", "")
        print(f"✅ model_pipeline success: {dish_name} | nutrition lines: {len(nutrition_info.splitlines())}")

        # 解析营养数值
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
        # Fallback: 直接用 Gemini vision 估算
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

    # ── Step 2: 对比计划（按营养范围，不按食物一一匹配）──
    planned_cal  = planned_meal.get("total_calories", 0) if planned_meal else 0
    planned_prot = planned_meal.get("total_protein", 0) if planned_meal else 0
    planned_carbs = planned_meal.get("total_carbs", 0) if planned_meal else 0
    planned_fat  = planned_meal.get("total_fat", 0) if planned_meal else 0

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
    compliance_score = int(sum(scores) / len(scores)) if scores else 70  # 无计划时给默认70

    # ── Step 3: 个性化建议 ──
    tips = []
    if actual_sodium > 1500:
        tips.append(f"⚠️ High sodium ({actual_sodium}mg) — try to reduce salt in remaining meals today.")
    if planned_prot > 0 and actual_prot < planned_prot * 0.6:
        tips.append(f"💪 Low protein ({actual_prot}g vs {planned_prot}g planned) — add more protein in your next meal.")
    if planned_cal > 0 and actual_cal > planned_cal * 1.3:
        tips.append(f"🔥 Over calorie target by {actual_cal - planned_cal} kcal — consider lighter options later.")
    if actual_sugar > 40:
        tips.append(f"🍬 High sugar ({actual_sugar}g) — avoid sugary snacks for the rest of the day.")

    # 对比反馈
    if planned_cal > 0:
        cal_diff = actual_cal - planned_cal
        if abs(cal_diff) <= planned_cal * 0.15:
            feedback = f"Great match! Your meal is within the planned calorie range ({actual_cal} vs {planned_cal} kcal planned)."
        elif cal_diff > 0:
            feedback = f"Meal is {cal_diff} kcal over plan. Protein is {'on track' if within_range(actual_prot, planned_prot) else 'below target'}."
        else:
            feedback = f"Meal is {abs(cal_diff)} kcal under plan. Consider a healthy snack to meet your daily target."
    else:
        feedback = f"Meal analyzed: {actual_cal} kcal, {actual_prot}g protein, {actual_carbs}g carbs, {actual_fat}g fat."

    if tips:
        feedback += " " + tips[0]

    remaining_days = [d.get("day_name", "") for d in remaining_plan if d]
    adjustment_note = None
    if compliance_score < 60 and remaining_days:
        short = planned_prot > 0 and actual_prot < planned_prot * 0.7
        over  = planned_cal > 0 and actual_cal > planned_cal * 1.2
        if short:
            adjustment_note = f"To compensate for low protein, add an extra protein source (eggs, chicken, tofu) in your {remaining_days[0]} meals."
        elif over:
            adjustment_note = f"You're over calories today. For {remaining_days[0]}, reduce portion sizes by about 20% to stay on track."

    print(f"✅ Photo analyzed | score={compliance_score}% | {actual_cal}kcal P{actual_prot}g")

    return {
        # 分析结果（用于 Compliance 界面）
        "detected_foods": detected_foods,
        "estimated_calories": actual_cal,
        "estimated_protein": actual_prot,
        "estimated_carbs": actual_carbs,
        "estimated_fat": actual_fat,
        "compliance_score": compliance_score,
        "compliance_feedback": feedback,
        "plan_adjustment_note": adjustment_note,
        # 保存到 meal history 用的完整数据
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
