# model_pipeline.py
from PIL import Image
import google.generativeai as genai
import base64
import os
import re
import time
from datetime import datetime
from dotenv import load_dotenv
from pymongo import MongoClient
from io import BytesIO
import traceback
import json

load_dotenv()

GEN_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEN_API_KEY:
    raise ValueError("GEMINI_API_KEY is not set in environment variables.")

genai.configure(api_key=GEN_API_KEY)
gemini_model = genai.GenerativeModel('gemini-2.0-flash')

mongo_uri = os.getenv("MONGO_URI")
mongo_db = os.getenv("MONGO_DB", "food-app-swift")
if mongo_uri:
    client = MongoClient(mongo_uri)
    db = client[mongo_db]
    meals_collection = db["meals"]
else:
    print("⚠️ MongoDB not configured")
    meals_collection = None

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def analyze_image_single_pass(image_path):
    image = Image.open(image_path)
    image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
    if image.mode not in ('RGB', 'L'):
        image = image.convert('RGB')

    optimized_path = image_path.replace('.png', '_opt.jpg').replace('.jpg', '_opt.jpg')
    image.save(optimized_path, 'JPEG', quality=85)

    image_data = encode_image(optimized_path)
    try:
        os.remove(optimized_path)
    except:
        pass

    prompt = """Analyze this food image completely in ONE response. Return ONLY the sections below, no extra text.

=== DISH NAME ===
[The specific dish name]

=== VISIBLE INGREDIENTS ===
[Each ingredient you can see, one per line in format:]
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
- No placeholder or example values"""

    print("🔍 Single-pass analysis starting...")
    response = gemini_model.generate_content([
        prompt,
        {"mime_type": "image/jpeg", "data": image_data}
    ])

    if not response or not response.text:
        raise Exception("Empty response from Gemini")

    return response.text.strip()


def parse_single_pass_response(response_text):
    """Parse the single-pass Gemini response into structured data"""
    dish_name = ""
    visible_ingredients = []
    hidden_ingredients = []
    nutrition_lines = []

    current_section = None

    for line in response_text.split('\n'):
        line = line.strip()
        if not line:
            continue

        if '=== DISH NAME ===' in line:
            current_section = 'dish'
        elif '=== VISIBLE INGREDIENTS ===' in line:
            current_section = 'visible'
        elif '=== HIDDEN INGREDIENTS ===' in line:
            current_section = 'hidden'
        elif '=== NUTRITION ===' in line:
            current_section = 'nutrition'
        elif current_section == 'dish' and not dish_name:
            dish_name = line
        elif current_section == 'visible' and '|' in line:
            parts = line.split('|')
            if len(parts) >= 3 and not any(x in line.lower() for x in ['ingredient', 'quantity', '---']):
                visible_ingredients.append(line)
        elif current_section == 'hidden' and '|' in line:
            parts = line.split('|')
            if len(parts) >= 3 and not any(x in line.lower() for x in ['ingredient', 'quantity', '---']):
                hidden_ingredients.append(line)
        elif current_section == 'nutrition' and '|' in line:
            parts = line.split('|')
            if len(parts) >= 3:
                nutrient = parts[0].strip()
                value_str = re.sub(r'[^\d.]', '', parts[1].strip())
                unit = parts[2].strip()
                if value_str:
                    nutrition_lines.append(f"{nutrient}|{value_str}|{unit}")

    # Ensure all required nutrients present
    required = [
        ("Calories", "kcal"), ("Protein", "g"), ("Fat", "g"),
        ("Carbohydrates", "g"), ("Fiber", "g"), ("Sugar", "g"), ("Sodium", "mg")
    ]
    found = {line.split('|')[0].strip().lower(): line for line in nutrition_lines}
    final_nutrition = []
    for nutrient, unit in required:
        matched = next((v for k, v in found.items() if nutrient.lower() in k), None)
        if matched:
            final_nutrition.append(matched)
        else:
            final_nutrition.append(f"{nutrient}|0|{unit}")

    return {
        'dish_name': dish_name or "Unknown dish",
        'visible_ingredients': visible_ingredients,
        'hidden_ingredients': hidden_ingredients,
        'nutrition': '\n'.join(final_nutrition)
    }


def full_image_analysis(image_path, user_id):
    """Complete analysis - now single Gemini call instead of 3"""
    try:
        start_time = time.time()
        print(f"🤖 Starting single-pass analysis for user: {user_id}")

        raw_response = analyze_image_single_pass(image_path)
        parsed = parse_single_pass_response(raw_response)

        dish_name = parsed['dish_name']
        visible_ingredients = parsed['visible_ingredients']
        hidden_ingredients = parsed['hidden_ingredients']
        nutrition_info = parsed['nutrition']

        if len(visible_ingredients) < 1:
            raise Exception("No ingredients detected")

        analysis_time = time.time() - start_time
        print(f"✅ Single-pass analysis done in {analysis_time:.2f}s")
        print(f"   - Dish: {dish_name}")
        print(f"   - Visible: {len(visible_ingredients)}")
        print(f"   - Hidden: {len(hidden_ingredients)}")

        return {
            'dish_prediction': dish_name,
            'image_description': '\n'.join(visible_ingredients),
            'hidden_ingredients': '\n'.join(hidden_ingredients),
            'nutrition_info': nutrition_info,
            'analysis_time': analysis_time,
            'user_id': user_id,
            'analysis_confidence': min(100, len(visible_ingredients) * 10),
            'detection_stats': {
                'visible_count': len(visible_ingredients),
                'hidden_count': len(hidden_ingredients),
                'method': 'single_pass_v3'
            }
        }

    except Exception as e:
        print(f"❌ Analysis error: {str(e)}")
        traceback.print_exc()
        return {
            'dish_prediction': "Detection failed",
            'image_description': f"Error: {str(e)} | 0 | items | Failed",
            'hidden_ingredients': "",
            'nutrition_info': "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg",
            'analysis_time': 0,
            'user_id': user_id,
            'error': str(e),
            'analysis_confidence': 0
        }


def recalculate_nutrition_enhanced(ingredients_text):
    """Recalculate nutrition from edited ingredients"""
    try:
        prompt = f"""Calculate nutritional values for these exact ingredients:

{ingredients_text}

Return ONLY these lines, no other text:
Calories|VALUE|kcal
Protein|VALUE|g
Fat|VALUE|g
Carbohydrates|VALUE|g
Fiber|VALUE|g
Sugar|VALUE|g
Sodium|VALUE|mg"""

        response = gemini_model.generate_content(prompt)

        if response and response.text:
            lines = response.text.strip().split('\n')
            has_real = any(
                '|' in l and float(re.sub(r'[^\d.]', '', l.split('|')[1]) or '0') > 0
                for l in lines if '|' in l and len(l.split('|')) >= 2
            )
            if has_real:
                return response.text.strip()

        raise Exception("No valid response")

    except Exception as e:
        print(f"❌ Recalculation failed: {str(e)}")
        return "Calories|0|kcal\nProtein|0|g\nFat|0|g\nCarbohydrates|0|g\nFiber|0|g\nSugar|0|g\nSodium|0|mg"


def validate_image_for_analysis(image_path):
    try:
        with Image.open(image_path) as img:
            if img.width < 100 or img.height < 100:
                return False, "Image too small for analysis"
            if img.format not in ['JPEG', 'PNG', 'WEBP', None]:
                return False, f"Unsupported format: {img.format}"
            extrema = img.convert("L").getextrema()
            if extrema == (0, 0) or extrema == (255, 255):
                return False, "Image appears to be blank"
            return True, "Image is valid"
    except Exception as e:
        return False, f"Invalid image: {str(e)}"
