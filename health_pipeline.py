import google.generativeai as genai
import os
import json
import traceback
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()


GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if GEN_API_KEY:
    genai.configure(api_key=GEN_API_KEY)
    _model = genai.GenerativeModel('gemini-2.5-pro')
else:
    _model = None
    print("⚠️ health_pipeline: GEMINI_API_KEY not set")


def _get_model(gemini_model=None):
   
    return gemini_model or _model


# ════════════════════════════════════════════════════════════════
# 1. Generate health/nutrition goal
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

def generate_weekly_meal_plan(nutrition_plan: dict, health_profile: dict, gemini_model=None) -> dict:
    """
    根据营养计划和健康档案，生成 7 天 × 3 餐的饮食计划。
    返回符合 WeeklyMealPlan 数据模型的 dict。
    """
    model = _get_model(gemini_model)
    if not model:
        raise Exception("Gemini model not available")

    # 计算本周日期列表（周一开始）
    today      = datetime.now()
    week_start = today - timedelta(days=today.weekday())
    day_names  = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    days_info  = []
    for i in range(7):
        d = week_start + timedelta(days=i)
        days_info.append({"date": d.strftime("%Y-%m-%d"), "day_name": day_names[i]})

    dates_str = ", ".join(d["date"] for d in days_info)

    prompt = f"""You are a clinical dietitian. Create a complete 7-day meal plan.

Daily nutrition targets:
- Calories: {nutrition_plan.get('daily_calories', 2000)} kcal
- Protein: {nutrition_plan.get('protein_g', 100)}g
- Carbohydrates: {nutrition_plan.get('carbs_g', 250)}g
- Fat: {nutrition_plan.get('fat_g', 65)}g
- Fiber: {nutrition_plan.get('fiber_g', 25)}g
- Sodium: {nutrition_plan.get('sodium_mg', 2000)}mg

Patient restrictions:
- Dietary preferences: {', '.join(health_profile.get('dietary_preferences', ['none']))}
- Allergens to STRICTLY avoid: {', '.join(health_profile.get('allergens', ['none']))}

Create exactly 7 days with dates: {dates_str}
Each day has breakfast, lunch, and dinner.
Each meal has specific food items with gram weights.

Respond ONLY with valid JSON, no markdown:
{{
  "week_start_date": "{days_info[0]['date']}",
  "days": [
    {{
      "date": "{days_info[0]['date']}",
      "day_name": "Monday",
      "breakfast": {{
        "meal_type": "breakfast",
        "name": "<descriptive meal name>",
        "items": [
          {{
            "food": "<specific food name>",
            "amount_g": <number>,
            "calories": <integer>,
            "protein": <number>,
            "carbs": <number>,
            "fat": <number>
          }}
        ],
        "total_calories": <integer>,
        "total_protein": <integer>,
        "total_carbs": <integer>,
        "total_fat": <integer>,
        "notes": "<optional cooking tip or substitution>"
      }},
      "lunch": {{ <same structure as breakfast> }},
      "dinner": {{ <same structure as breakfast> }},
      "total_calories": <integer>
    }},
    ... (6 more days for {", ".join(d["date"] for d in days_info[1:])})
  ]
}}"""

    print(f"🍽️ Generating 7-day meal plan | target={nutrition_plan.get('daily_calories')} kcal/day")
    response = model.generate_content(prompt)
    text = response.text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(text)

    print(f"✅ Meal plan generated | {len(result.get('days', []))} days")
    return result


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